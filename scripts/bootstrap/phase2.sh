#!/usr/bin/env bash
# phase2.sh — Phase 2: Register secrets, commit workflows & SECRETS.md
# Requires: MIRROR_TOKEN, GITOPS_TOKEN env vars set before execution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

WORKFLOW_DIR="$SCRIPT_DIR/lib/workflows"

# ─── Helpers ────────────────────────────────────────────────────────

workflows_for_repo() {
  local repo="$1"
  case "$repo" in
    synapse-platform-svc|synapse-engagement-svc)
      echo "mirror.yml ci-java.yml deploy.yml" ;;
    synapse-knowledge-svc)
      echo "mirror.yml ci-java.yml deploy.yml" ;;
    synapse-learning-svc)
      echo "mirror.yml ci-java.yml deploy.yml" ;;
    synapse-frontend)
      echo "mirror.yml ci-flutter.yml" ;;
    synapse-shared)
      echo "mirror.yml ci-java.yml schema-check.yml" ;;
    synapse-gitops)
      echo "validate-manifests.yml" ;;
    synapse-mirror)
      echo "" ;;  # no workflows
    *)
      log_warn "Unknown repo: $repo — skipping workflows"
      echo "" ;;
  esac
}

track_specific_rows_for_repo() {
  local repo="$1"
  case "$repo" in
    synapse-platform-svc)
      cat <<'ROWS'
| `ECR_REGISTRY` | Docker 이미지 레지스트리 주소 | AWS ECR | Platform | ⬜ 미등록 | — | Phase 3 등록 예정 |
| `OAUTH_CLIENT_SECRET` | OAuth 2.0 소셜 로그인 | Google/Kakao Console | Platform | ⬜ 미등록 | — | 발급 후 등록 |
| `STRIPE_SECRET_KEY` | 결제 연동 | Stripe Dashboard | Platform | ⬜ 미등록 | — | 테스트 키 우선 |
| `FCM_SERVICE_ACCOUNT` | Firebase 푸시 알림 | Firebase Console | Platform | ⬜ 미등록 | — | JSON key base64 인코딩 |
ROWS
      ;;
    synapse-engagement-svc)
      cat <<'ROWS'
| `ECR_REGISTRY` | Docker 이미지 레지스트리 주소 | AWS ECR | Platform | ⬜ 미등록 | — | Phase 3 등록 예정 |
ROWS
      ;;
    synapse-knowledge-svc)
      cat <<'ROWS'
| `ECR_REGISTRY` | Docker 이미지 레지스트리 주소 | AWS ECR | Knowledge | ⬜ 미등록 | — | Phase 3 등록 예정 |
| `S3_BUCKET_NAME` | 노트 첨부파일 저장 | AWS S3 | Knowledge | ⬜ 미등록 | — | 버킷 생성 후 등록 |
| `ES_ENDPOINT` | Elasticsearch 검색 엔진 | AWS OpenSearch | Knowledge | ⬜ 미등록 | — | 클러스터 프로비저닝 후 |
ROWS
      ;;
    synapse-learning-svc)
      cat <<'ROWS'
| `ECR_REGISTRY` | Docker 이미지 레지스트리 주소 | AWS ECR | Learning | ⬜ 미등록 | — | Phase 3 등록 예정 |
| `ANTHROPIC_API_KEY` | Claude AI 연동 | Anthropic Console | Learning | ⬜ 미등록 | — | 팀 API key |
| `OPENAI_API_KEY` | OpenAI 연동 (fallback) | OpenAI Dashboard | Learning | ⬜ 미등록 | — | 팀 API key |
ROWS
      ;;
    synapse-frontend)
      cat <<'ROWS'
ROWS
      ;;
    synapse-shared)
      cat <<'ROWS'
| `SCHEMA_REGISTRY_URL` | Avro 스키마 호환성 검증 | Confluent / self-hosted | Shared | ⬜ 미등록 | — | Phase 3 등록 예정 |
ROWS
      ;;
    *)
      echo "" ;;
  esac
}

# ─── Step 1: Register secrets ──────────────────────────────────────

register_all_secrets() {
  log_info "=== Registering MIRROR_TOKEN + GITOPS_TOKEN for all Tier 1 repos ==="
  local count=0

  for repo in "${TIER1_NAMES[@]}"; do
    for secret_name in MIRROR_TOKEN GITOPS_TOKEN; do
      if secret_exists "$repo" "$secret_name"; then
        log_ok "$repo/$secret_name already registered — skipping"
      else
        log_info "Setting $secret_name on $ORG/$repo ..."
        echo "${!secret_name}" | gh secret set "$secret_name" --repo "$ORG/$repo"
        log_ok "$repo/$secret_name registered"
      fi
      count=$((count + 1))
    done
  done

  log_ok "Secret registration complete ($count secret slots processed)"
}

# ─── Step 2: Commit workflows per repo ─────────────────────────────

commit_one_workflow_set() {
  local repo="$1"
  local wf_list
  wf_list="$(workflows_for_repo "$repo")"

  if [ -z "$wf_list" ]; then
    log_info "$repo — no workflows to install"
    return 0
  fi

  log_info "Installing workflows for $repo ..."

  local clone_dir="$BOOTSTRAP_TMP/$repo"
  if [ ! -d "$clone_dir/.git" ]; then
    gh repo clone "$ORG/$repo" "$clone_dir" -- --depth 1
  fi

  mkdir -p "$clone_dir/.github/workflows"

  for wf in $wf_list; do
    if [ ! -f "$WORKFLOW_DIR/$wf" ]; then
      log_error "Workflow template not found: $WORKFLOW_DIR/$wf"
      return 1
    fi
    cp "$WORKFLOW_DIR/$wf" "$clone_dir/.github/workflows/$wf"
    log_ok "  copied $wf"
  done

  # Write SECRETS.md for Tier 1 repos
  local is_tier1=false
  for t1 in "${TIER1_NAMES[@]}"; do
    if [ "$t1" = "$repo" ]; then
      is_tier1=true
      break
    fi
  done

  if $is_tier1; then
    local track_rows
    track_rows="$(track_specific_rows_for_repo "$repo")"
    sed \
      -e "s/{{REPO_NAME}}/$repo/g" \
      -e "/{{TRACK_SPECIFIC_ROWS}}/r /dev/stdin" \
      -e "/{{TRACK_SPECIFIC_ROWS}}/d" \
      "$WORKFLOW_DIR/SECRETS.md.tmpl" > "$clone_dir/SECRETS.md" \
      <<< "$track_rows"
    log_ok "  wrote SECRETS.md"
  fi

  pushd "$clone_dir" > /dev/null
  git config user.name "bootstrap[bot]"
  git config user.email "bootstrap[bot]@users.noreply.github.com"
  git add -A
  if git diff --cached --quiet; then
    log_info "$repo — no workflow changes to commit"
  else
    git commit -m "ci: add GitHub Actions workflows (Phase 2 bootstrap)"
    git push
    log_ok "$repo — workflows committed and pushed"
  fi
  popd > /dev/null
}

# ─── Step 3: Loop all repos ────────────────────────────────────────

commit_all_workflows() {
  log_info "=== Installing workflows for all repos ==="
  mkdir -p "$BOOTSTRAP_TMP"

  for repo in "${ALL_REPO_NAMES[@]}"; do
    commit_one_workflow_set "$repo"
  done

  log_ok "All workflow sets installed"
}

# ─── Step 4: Gate 2 validation ─────────────────────────────────────

gate2_validate() {
  log_info "=== Gate 2 Validation ==="
  local report_file
  report_file="$(report_init "phase2")"

  # Check 1: 12 secrets registered (6 repos x 2 secrets)
  local secret_count=0
  for repo in "${TIER1_NAMES[@]}"; do
    for secret_name in MIRROR_TOKEN GITOPS_TOKEN; do
      if secret_exists "$repo" "$secret_name"; then
        secret_count=$((secret_count + 1))
      fi
    done
  done
  report_row "$report_file" "Secrets registered" "12" "$secret_count"

  # Check 2: 7 repos have workflows (all except synapse-mirror)
  local wf_count=0
  for repo in "${ALL_REPO_NAMES[@]}"; do
    local clone_dir="$BOOTSTRAP_TMP/$repo"
    if [ -d "$clone_dir/.github/workflows" ] && [ "$(ls -A "$clone_dir/.github/workflows" 2>/dev/null)" ]; then
      wf_count=$((wf_count + 1))
    fi
  done
  report_row "$report_file" "Repos with workflows" "7" "$wf_count"

  # Check 3: 6 repos have SECRETS.md (all Tier 1)
  local secrets_md_count=0
  for repo in "${TIER1_NAMES[@]}"; do
    local clone_dir="$BOOTSTRAP_TMP/$repo"
    if [ -f "$clone_dir/SECRETS.md" ]; then
      secrets_md_count=$((secrets_md_count + 1))
    fi
  done
  report_row "$report_file" "Repos with SECRETS.md" "6" "$secrets_md_count"

  log_ok "Gate 2 report written: $report_file"

  # Fail if any check didn't pass
  if [ "$secret_count" -ne 12 ] || [ "$wf_count" -ne 7 ] || [ "$secrets_md_count" -ne 6 ]; then
    log_error "Gate 2 FAILED — see report for details"
    return 1
  fi

  log_ok "Gate 2 PASSED"
}

# ─── Main ──────────────────────────────────────────────────────────

main() {
  log_info "Phase 2: Secrets + Workflows + SECRETS.md"
  require_env MIRROR_TOKEN
  require_env GITOPS_TOKEN

  register_all_secrets
  commit_all_workflows
  gate2_validate

  log_ok "Phase 2 complete"
}

main "$@"
