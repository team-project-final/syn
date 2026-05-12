#!/usr/bin/env bash
# phase3.sh — Phase 3: Scaffold all services, push, validate, finalize
# Part of the polyrepo bootstrap plan.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# shellcheck source=lib/scaffolds/spring-init.sh
. "$SCRIPT_DIR/lib/scaffolds/spring-init.sh"
# shellcheck source=lib/scaffolds/learning-ai-fastapi.sh
. "$SCRIPT_DIR/lib/scaffolds/learning-ai-fastapi.sh"
# shellcheck source=lib/scaffolds/frontend-flutter.sh
. "$SCRIPT_DIR/lib/scaffolds/frontend-flutter.sh"
# shellcheck source=lib/scaffolds/shared-avro.sh
. "$SCRIPT_DIR/lib/scaffolds/shared-avro.sh"
# shellcheck source=lib/scaffolds/gitops-manifests.sh
. "$SCRIPT_DIR/lib/scaffolds/gitops-manifests.sh"

REPORT=$(report_init "phase3")
log_info "Phase 3 시작 — scaffold, push, validate, finalize"

###############################################################################
# 1. scaffold_java_backends — Spring Boot + Modulith for 3 Java backends
###############################################################################
scaffold_java_backends() {
  log_info "=== Java 백엔드 스캐폴딩 시작 ==="

  for repo_name in "${JAVA_BACKEND_NAMES[@]}"; do
    local repo_dir="$BOOTSTRAP_TMP/$repo_name"
    # Derive artifact name: synapse-platform-svc → platform-svc
    local artifact="${repo_name#synapse-}"
    # Derive package: synapse-platform-svc → com.synapse.platform
    local svc_short="${artifact%-svc}"
    local pkg="com.synapse.${svc_short}"

    log_info "스캐폴딩: $repo_name (artifact=$artifact, pkg=$pkg)"

    spring_init "$repo_dir" "$repo_name" "$artifact" "$pkg"

    # Get modules for this repo
    local mod_list="${MODULES[$repo_name]}"
    # shellcheck disable=SC2086
    spring_create_modules "$repo_dir" "$pkg" $mod_list

    spring_create_modulith_test "$repo_dir" "$pkg" "$artifact"

    log_ok "Java 백엔드 스캐폴딩 완료: $repo_name"
  done

  log_ok "=== Java 백엔드 스캐폴딩 완료 ==="
}

###############################################################################
# 2. scaffold_learning_svc — learning-card (Java) + learning-ai (Python)
###############################################################################
scaffold_learning_svc() {
  log_info "=== learning-svc 스캐폴딩 시작 ==="

  local repo_name="synapse-learning-svc"
  local repo_dir="$BOOTSTRAP_TMP/$repo_name"
  local artifact="learning-card"
  local pkg="com.synapse.learning"

  # learning-card as sub-project: Spring init into learning-card/ subdir
  local card_dir="$repo_dir/learning-card"
  mkdir -p "$card_dir"

  spring_init "$card_dir" "$repo_name" "$artifact" "$pkg"

  # No explicit modulith modules for learning-card — it is a single module
  # But we still create a modulith test
  spring_create_modulith_test "$card_dir" "$pkg" "$artifact"

  # Root settings.gradle.kts for multi-project
  cat > "$repo_dir/settings.gradle.kts" <<'GRADLE'
rootProject.name = "synapse-learning-svc"

include("learning-card")
GRADLE

  # learning-ai (FastAPI)
  learning_ai_init "$repo_dir"

  log_ok "=== learning-svc 스캐폴딩 완료 ==="
}

###############################################################################
# 3. scaffold_frontend — Flutter project (with fallback)
###############################################################################
scaffold_frontend() {
  log_info "=== frontend 스캐폴딩 시작 ==="

  local repo_name="synapse-frontend"
  local repo_dir="$BOOTSTRAP_TMP/$repo_name"

  if command -v flutter &>/dev/null; then
    frontend_init "$repo_dir"
  else
    log_warn "flutter CLI 미설치 — placeholder 생성"
    mkdir -p "$repo_dir/lib"
    cat > "$repo_dir/lib/main.dart" <<'DART'
// Placeholder — flutter CLI가 설치되지 않아 자동 생성됨.
// flutter create --org com.synapse --platforms web,android,ios 로 재생성하세요.
void main() {}
DART
    cat > "$repo_dir/README.md" <<'MD'
# synapse-frontend

Flutter 프로젝트 placeholder. flutter CLI 설치 후 다시 scaffold 하세요.
MD
  fi

  log_ok "=== frontend 스캐폴딩 완료 ==="
}

###############################################################################
# 4. scaffold_shared — Avro schemas
###############################################################################
scaffold_shared() {
  log_info "=== shared 스캐폴딩 시작 ==="

  local repo_dir="$BOOTSTRAP_TMP/synapse-shared"
  shared_init "$repo_dir"

  log_ok "=== shared 스캐폴딩 완료 ==="
}

###############################################################################
# 5. scaffold_gitops — Kubernetes manifests + ArgoCD
###############################################################################
scaffold_gitops() {
  log_info "=== gitops 스캐폴딩 시작 ==="

  local repo_dir="$BOOTSTRAP_TMP/synapse-gitops"
  gitops_init "$repo_dir"

  log_ok "=== gitops 스캐폴딩 완료 ==="
}

###############################################################################
# 6. push_all_scaffolds — git add/commit/push for each non-mirror repo
###############################################################################
push_all_scaffolds() {
  log_info "=== 스캐폴드 push 시작 ==="

  for repo_name in "${ALL_REPO_NAMES[@]}"; do
    # Skip mirror — it's auto-synced
    if [ "$repo_name" = "synapse-mirror" ]; then
      log_info "mirror repo 건너뜀: $repo_name"
      continue
    fi

    local repo_dir="$BOOTSTRAP_TMP/$repo_name"

    if [ ! -d "$repo_dir" ]; then
      log_warn "디렉터리 없음 — 건너뜀: $repo_dir"
      continue
    fi

    git -C "$repo_dir" add -A

    if git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
      log_warn "$repo_name: 변경 사항 없음 — push 건너뜀"
      continue
    fi

    git -C "$repo_dir" commit -m "chore: Phase 3 scaffold — project structure + CI

Includes Spring Boot / FastAPI / Flutter / Avro scaffolds,
GitHub Actions CI, and Kubernetes manifests."

    git -C "$repo_dir" push origin main

    log_ok "push 완료: $repo_name"
  done

  log_ok "=== 스캐폴드 push 완료 ==="
}

###############################################################################
# 7. gate3_validate — Phase 3 validation checks
###############################################################################
gate3_validate() {
  log_info "=== Gate 3 검증 시작 ==="
  local pass=true

  # Check 1: Tier 1 Actions run success — expect 6
  local actions_ok=0
  for repo_name in "${TIER1_NAMES[@]}"; do
    local status
    status=$(gh run list --repo "$ORG/$repo_name" --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "")
    if [ "$status" = "success" ]; then
      actions_ok=$((actions_ok + 1))
    else
      log_warn "Actions 실패/미실행: $repo_name (status=$status)"
    fi
  done
  report_row "$REPORT" "Tier1 Actions success" "6" "$actions_ok"
  [ "$actions_ok" -ne 6 ] && pass=false

  # Check 2: mirror services/ dirs — expect 6
  local mirror_dirs=0
  local mirror_dir="$BOOTSTRAP_TMP/synapse-mirror"
  if [ -d "$mirror_dir" ]; then
    # Pull latest
    git -C "$mirror_dir" pull --ff-only origin main 2>/dev/null || true
  else
    gh repo clone "$ORG/synapse-mirror" "$mirror_dir" 2>/dev/null || true
  fi
  for repo_name in "${TIER1_NAMES[@]}"; do
    local svc_dir="${repo_name#synapse-}"
    if [ -d "$mirror_dir/$svc_dir" ]; then
      mirror_dirs=$((mirror_dirs + 1))
    fi
  done
  report_row "$REPORT" "mirror service dirs" "6" "$mirror_dirs"
  [ "$mirror_dirs" -ne 6 ] && pass=false

  # Check 3: gitops ApplicationSet — expect 1
  local appset_count=0
  if [ -f "$BOOTSTRAP_TMP/synapse-gitops/argocd/applicationset.yaml" ]; then
    appset_count=1
  fi
  report_row "$REPORT" "gitops ApplicationSet" "1" "$appset_count"
  [ "$appset_count" -ne 1 ] && pass=false

  # Check 4: UserRegistered.avsc — expect 1
  local user_reg_count=0
  if [ -f "$BOOTSTRAP_TMP/synapse-shared/src/main/avro/platform/UserRegistered.avsc" ]; then
    user_reg_count=1
  fi
  report_row "$REPORT" "UserRegistered.avsc" "1" "$user_reg_count"
  [ "$user_reg_count" -ne 1 ] && pass=false

  log_info "검증 리포트: $REPORT"

  if [ "$pass" = true ]; then
    log_ok "=== Gate 3 검증 통과 ==="
  else
    log_error "=== Gate 3 검증 실패 — 리포트를 확인하세요 ==="
    exit 1
  fi
}

###############################################################################
# 8. finalize_protection — enforce_admins for all repos
###############################################################################
finalize_protection() {
  log_info "=== enforce_admins 활성화 시작 ==="

  for repo_name in "${ALL_REPO_NAMES[@]}"; do
    log_info "enforce_admins 설정 중: $repo_name"

    gh api -X PATCH "repos/$ORG/$repo_name/branches/main/protection/enforce_admins" \
      --method POST >/dev/null 2>&1 || {
      log_warn "enforce_admins 설정 실패: $repo_name"
    }

    log_ok "enforce_admins 완료: $repo_name"
  done

  log_ok "=== enforce_admins 활성화 완료 ==="
}

###############################################################################
# main
###############################################################################
main() {
  scaffold_java_backends
  scaffold_learning_svc
  scaffold_frontend
  scaffold_shared
  scaffold_gitops
  push_all_scaffolds

  log_info "Gate 3 검증 전 60초 대기 (CI 완료 대기)…"
  sleep 60

  gate3_validate
  finalize_protection

  log_ok "Phase 3 완료"
}

main "$@"
