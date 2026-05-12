#!/usr/bin/env bash
# phase1.sh — Phase 1: Repo creation, initial commits, branch protection
# Part of the polyrepo bootstrap plan.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

REPORT=$(report_init "phase1")
log_info "Phase 1 시작 — repo creation, initial commits, branch protection"

###############################################################################
# 1. ensure_gh_auth — verify CLI auth + org admin role
###############################################################################
ensure_gh_auth() {
  log_info "gh 인증 상태 확인 중…"
  if ! gh auth status >/dev/null 2>&1; then
    log_error "gh auth status 실패 — 먼저 gh auth login 을 실행하세요."
    exit 1
  fi
  log_ok "gh CLI 인증 확인됨"

  log_info "조직 $ORG 의 admin 권한 확인 중…"
  local role
  role=$(gh api "user/memberships/orgs/$ORG" --jq '.role' 2>/dev/null || true)
  if [ "$role" != "admin" ]; then
    log_error "조직 $ORG 에서 admin 권한이 필요합니다 (현재: ${role:-없음})"
    exit 1
  fi
  log_ok "조직 admin 권한 확인됨"
}

###############################################################################
# 2. create_one_repo — idempotent single repo creation
#    args: name, visibility, description, topics_csv
###############################################################################
create_one_repo() {
  local name="$1" visibility="$2" description="$3" topics_csv="$4"

  if repo_exists "$name"; then
    log_warn "repo $ORG/$name 이미 존재 — 건너뜀"
    return 0
  fi

  log_info "repo 생성 중: $ORG/$name ($visibility)"
  gh repo create "$ORG/$name" \
    --"$visibility" \
    --description "$description" \
    --clone=false

  # Common settings
  gh repo edit "$ORG/$name" \
    --enable-issues=true \
    --enable-wiki=false \
    --delete-branch-on-merge=true \
    --enable-squash-merge=true \
    --enable-rebase-merge=false

  # gitops: merge-commit only (disable squash)
  if [ "$name" = "synapse-gitops" ]; then
    gh repo edit "$ORG/$name" \
      --enable-merge-commit=true \
      --enable-squash-merge=false
  else
    gh repo edit "$ORG/$name" \
      --enable-merge-commit=false
  fi

  # Add topics
  IFS=',' read -ra topic_arr <<< "$topics_csv"
  for topic in "${topic_arr[@]}"; do
    gh repo edit "$ORG/$name" --add-topic "$topic"
  done

  log_ok "repo 생성 완료: $ORG/$name"
}

###############################################################################
# 3. create_all_repos — iterate Tier1 + mirror + gitops
###############################################################################
create_all_repos() {
  log_info "=== 전체 repo 생성 시작 ==="

  for entry in "${TIER1_REPOS[@]}"; do
    IFS='|' read -r name vis desc topics <<< "$entry"
    create_one_repo "$name" "$vis" "$desc" "$topics"
  done

  IFS='|' read -r name vis desc topics <<< "$MIRROR_REPO"
  create_one_repo "$name" "$vis" "$desc" "$topics"

  IFS='|' read -r name vis desc topics <<< "$GITOPS_REPO"
  create_one_repo "$name" "$vis" "$desc" "$topics"

  log_ok "=== 전체 repo 생성 완료 ==="
}

###############################################################################
# 4. write_gitignore — language-aware .gitignore
###############################################################################
write_gitignore() {
  local name="$1" target_dir="$2"
  local file="$target_dir/.gitignore"

  # Common ignores
  cat > "$file" <<'GITIGNORE'
# === IDE ===
.idea/
*.iml
.vscode/
*.swp
*.swo
*~

# === Environment ===
.env
.env.*
!.env.example

# === OS ===
.DS_Store
Thumbs.db
Desktop.ini
GITIGNORE

  # Java / Gradle
  case "$name" in
    synapse-platform-svc|synapse-engagement-svc|synapse-knowledge-svc|synapse-learning-svc|synapse-shared)
      cat >> "$file" <<'JAVA'

# === Java / Gradle ===
build/
.gradle/
!gradle/wrapper/gradle-wrapper.jar
bin/
out/
*.class
*.jar
*.war
*.ear
hs_err_pid*
JAVA
      ;;
  esac

  # Python (learning-svc multi-module)
  case "$name" in
    synapse-learning-svc)
      cat >> "$file" <<'PYTHON'

# === Python ===
__pycache__/
*.py[cod]
*.egg-info/
dist/
.venv/
venv/
.mypy_cache/
.ruff_cache/
.pytest_cache/
PYTHON
      ;;
  esac

  # Flutter / Dart
  case "$name" in
    synapse-frontend)
      cat >> "$file" <<'FLUTTER'

# === Flutter / Dart ===
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
*.g.dart
*.freezed.dart
pubspec.lock
FLUTTER
      ;;
  esac

  # Kubernetes / GitOps
  case "$name" in
    synapse-gitops)
      cat >> "$file" <<'K8S'

# === Kubernetes / GitOps ===
*.decoded
secrets/
!secrets/.gitkeep
K8S
      ;;
  esac
}

###############################################################################
# 5. write_editorconfig — standard .editorconfig
###############################################################################
write_editorconfig() {
  local target_dir="$1"
  cat > "$target_dir/.editorconfig" <<'EDITORCONFIG'
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.{java,py}]
indent_size = 4

[*.{dart,yaml,yml}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab
EDITORCONFIG
}

###############################################################################
# 6. setup_one_initial_commit — clone + seed files + push
###############################################################################
setup_one_initial_commit() {
  local name="$1"
  local clone_dir="$BOOTSTRAP_TMP/$name"

  if [ -d "$clone_dir" ]; then
    log_warn "이미 클론 디렉터리 존재: $clone_dir — 재사용"
  fi

  mkdir -p "$BOOTSTRAP_TMP"

  # Clone (init if empty repo)
  if [ ! -d "$clone_dir" ]; then
    if gh repo clone "$ORG/$name" "$clone_dir" 2>/dev/null; then
      log_info "클론 완료: $ORG/$name"
    else
      # Empty repo — init locally
      log_info "빈 repo 초기화: $name"
      mkdir -p "$clone_dir"
      git -C "$clone_dir" init -b main
      git -C "$clone_dir" remote add origin "https://github.com/$ORG/$name.git"
    fi
  fi

  # --- README.md ---
  case "$name" in
    synapse-platform-svc)
      cat > "$clone_dir/README.md" <<'README'
# synapse-platform-svc

Synapse 플랫폼 핵심 서비스 — Auth · Audit · Billing · Notification

## Modules

| Module | 설명 |
|---|---|
| `auth` | 인증/인가 (JWT, OAuth2) |
| `audit` | 감사 로그 |
| `billing` | 구독/결제 |
| `notification` | 알림 (email, push) |

## Tech Stack
- Java 21 · Spring Boot 3.4 · Spring Modulith
- PostgreSQL · Kafka · Redis
README
      ;;
    synapse-mirror)
      cat > "$clone_dir/README.md" <<'README'
# synapse-mirror

Tier 1 서비스 레포들의 자동 동기화 읽기 전용 미러.

> ⚠ 이 repo 는 자동 생성됩니다. 직접 수정하지 마세요.

## 구조
각 서비스가 top-level 디렉터리로 동기화됩니다.
README
      ;;
    synapse-gitops)
      cat > "$clone_dir/README.md" <<'README'
# synapse-gitops

Kubernetes 매니페스트 + ArgoCD ApplicationSet 관리.

## 구조
```
envs/
  dev/
  staging/
  prod/
apps/
  base/
```

## 배포 방식
- ArgoCD ApplicationSet 기반 GitOps
- PR merge → ArgoCD 자동 sync
README
      ;;
    *)
      # Generic README
      local desc=""
      for entry in "${TIER1_REPOS[@]}"; do
        IFS='|' read -r ename _ edesc _ <<< "$entry"
        if [ "$ename" = "$name" ]; then
          desc="$edesc"
          break
        fi
      done
      cat > "$clone_dir/README.md" <<README
# $name

$desc

## Getting Started

> 부트스트랩 초기 커밋입니다. 상세 내용은 곧 추가됩니다.
README
      ;;
  esac

  # --- CODEOWNERS ---
  mkdir -p "$clone_dir/.github"
  cat > "$clone_dir/.github/CODEOWNERS" <<'CODEOWNERS'
* @VelkaressiaBlutkrone
CODEOWNERS

  # --- .gitignore ---
  write_gitignore "$name" "$clone_dir"

  # --- .editorconfig ---
  write_editorconfig "$clone_dir"

  # --- Commit & push ---
  git -C "$clone_dir" add -A
  if git -C "$clone_dir" diff --cached --quiet 2>/dev/null; then
    log_warn "$name: 변경 사항 없음 — 커밋 건너뜀"
    return 0
  fi
  git -C "$clone_dir" commit -m "chore: bootstrap initial commit

Includes README.md, .github/CODEOWNERS, .gitignore, .editorconfig"
  git -C "$clone_dir" push -u origin main

  log_ok "초기 커밋 완료: $ORG/$name"
}

###############################################################################
# 7. setup_all_initial_commits
###############################################################################
setup_all_initial_commits() {
  log_info "=== 전체 초기 커밋 시작 ==="
  for name in "${ALL_REPO_NAMES[@]}"; do
    setup_one_initial_commit "$name"
  done
  log_ok "=== 전체 초기 커밋 완료 ==="
}

###############################################################################
# 8. setup_one_protection — branch protection via API
#    args: name, require_pr (true/false), require_linear (true/false)
###############################################################################
setup_one_protection() {
  local name="$1" require_pr="$2" require_linear="$3"

  log_info "브랜치 보호 설정 중: $name (PR=$require_pr, linear=$require_linear)"

  local pr_reviews_json="null"
  if [ "$require_pr" = "true" ]; then
    pr_reviews_json='{
      "required_approving_review_count": 1,
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "dismissal_restrictions": {}
    }'
  fi

  local payload
  payload=$(cat <<PJSON
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": $pr_reviews_json,
  "restrictions": null,
  "required_linear_history": $require_linear,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
PJSON
  )

  if gh api -X PUT "repos/$ORG/$name/branches/main/protection" \
    --input - <<< "$payload" >/dev/null 2>&1; then
    log_ok "브랜치 보호 완료: $name"
  else
    log_warn "브랜치 보호 실패 (private repo on free plan?): $name — 건너뜀"
  fi
}

###############################################################################
# 9. setup_all_branch_protection
###############################################################################
setup_all_branch_protection() {
  log_info "=== 전체 브랜치 보호 설정 시작 ==="

  # Tier1 (6) + shared + frontend: PR required + linear history
  for name in "${TIER1_NAMES[@]}"; do
    setup_one_protection "$name" "true" "true"
  done

  # mirror: PR off, linear off
  setup_one_protection "synapse-mirror" "false" "false"

  # gitops: PR on, linear off (merge-commit 필요)
  setup_one_protection "synapse-gitops" "true" "false"

  log_ok "=== 전체 브랜치 보호 설정 완료 ==="
}

###############################################################################
# 10. gate1_validate — 7 validation checks
###############################################################################
gate1_validate() {
  log_info "=== Gate 1 검증 시작 ==="
  local pass=true

  # Check 1: repos created — expect 8
  local created_count=0
  for name in "${ALL_REPO_NAMES[@]}"; do
    if repo_exists "$name"; then
      created_count=$((created_count + 1))
    fi
  done
  report_row "$REPORT" "repos created" "8" "$created_count"
  [ "$created_count" -ne 8 ] && pass=false

  # Check 2: public repos — expect 6
  local public_count=0
  for name in "${ALL_REPO_NAMES[@]}"; do
    local vis
    vis=$(gh repo view "$ORG/$name" --json visibility --jq '.visibility' 2>/dev/null || echo "")
    if [ "$vis" = "PUBLIC" ]; then
      public_count=$((public_count + 1))
    fi
  done
  report_row "$REPORT" "public repos" "6" "$public_count"
  [ "$public_count" -ne 6 ] && pass=false

  # Check 3: private repos — expect 2
  local private_count=$((created_count - public_count))
  report_row "$REPORT" "private repos" "2" "$private_count"
  [ "$private_count" -ne 2 ] && pass=false

  # Check 4: main branch exists — expect 8
  local main_count=0
  for name in "${ALL_REPO_NAMES[@]}"; do
    if gh api "repos/$ORG/$name/branches/main" >/dev/null 2>&1; then
      main_count=$((main_count + 1))
    fi
  done
  report_row "$REPORT" "main branch exists" "8" "$main_count"
  [ "$main_count" -ne 8 ] && pass=false

  # Check 5: branch protection enabled — expect 8
  local protection_count=0
  for name in "${ALL_REPO_NAMES[@]}"; do
    if gh api "repos/$ORG/$name/branches/main/protection" >/dev/null 2>&1; then
      protection_count=$((protection_count + 1))
    fi
  done
  report_row "$REPORT" "protection enabled" "8" "$protection_count"
  [ "$protection_count" -ne 8 ] && pass=false

  # Check 6: require PR reviews — expect 7 (Tier1 6 + gitops 1; mirror excluded)
  local pr_required_count=0
  for name in "${ALL_REPO_NAMES[@]}"; do
    local pr_json
    pr_json=$(gh api "repos/$ORG/$name/branches/main/protection/required_pull_request_reviews" 2>/dev/null || echo "")
    if [ -n "$pr_json" ] && [ "$pr_json" != "null" ]; then
      pr_required_count=$((pr_required_count + 1))
    fi
  done
  report_row "$REPORT" "require PR reviews" "7" "$pr_required_count"
  [ "$pr_required_count" -ne 7 ] && pass=false

  # Check 7: force push blocked — expect 8
  local force_push_blocked=0
  for name in "${ALL_REPO_NAMES[@]}"; do
    local fp
    fp=$(gh api "repos/$ORG/$name/branches/main/protection" --jq '.allow_force_pushes.enabled' 2>/dev/null || echo "true")
    if [ "$fp" = "false" ]; then
      force_push_blocked=$((force_push_blocked + 1))
    fi
  done
  report_row "$REPORT" "force push blocked" "8" "$force_push_blocked"
  [ "$force_push_blocked" -ne 8 ] && pass=false

  log_info "검증 리포트: $REPORT"

  if [ "$pass" = true ]; then
    log_ok "=== Gate 1 검증 통과 ✅ ==="
  else
    log_error "=== Gate 1 검증 실패 — 리포트를 확인하세요 ==="
    exit 1
  fi
}

###############################################################################
# main
###############################################################################
main() {
  ensure_gh_auth
  create_all_repos
  setup_all_initial_commits
  setup_all_branch_protection
  gate1_validate
  log_ok "Phase 1 완료"
}

main "$@"
