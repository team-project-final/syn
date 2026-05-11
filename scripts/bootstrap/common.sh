#!/usr/bin/env bash
# common.sh — shared helpers for polyrepo bootstrap
# Sourced by phase1/2/3.sh. Idempotent.

set -euo pipefail

ORG="team-project-final"
SYN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_TMP="${BOOTSTRAP_TMP:-/tmp/bootstrap}"
REPORTS_DIR="$SYN_ROOT/scripts/bootstrap/reports"

# Color logging
log_info()  { printf "\033[36m[INFO]\033[0m  %s\n" "$*"; }
log_ok()    { printf "\033[32m[OK]\033[0m    %s\n" "$*"; }
log_warn()  { printf "\033[33m[WARN]\033[0m  %s\n" "$*"; }
log_error() { printf "\033[31m[ERROR]\033[0m %s\n" "$*" >&2; }

# Idempotent repo existence check
repo_exists() {
  local repo="$1"
  gh repo view "$ORG/$repo" >/dev/null 2>&1
}

# Idempotent secret existence check
secret_exists() {
  local repo="$1" secret_name="$2"
  gh secret list --repo "$ORG/$repo" --json name --jq '.[].name' 2>/dev/null \
    | grep -qx "$secret_name"
}

# Require env var or fail
require_env() {
  local var="$1"
  if [ -z "${!var:-}" ]; then
    log_error "Required environment variable not set: $var"
    log_error "See spec §4.2/§4.3 for PAT generation instructions."
    exit 1
  fi
}

# Markdown report writer
report_init() {
  local phase="$1"
  local date_iso
  date_iso=$(date -Iseconds)
  local report_file="$REPORTS_DIR/$phase-$(date +%F).md"
  cat > "$report_file" <<EOF
## $phase Report — $date_iso

| Check | Expected | Actual | Pass |
|---|---|:---:|:---:|
EOF
  echo "$report_file"
}

report_row() {
  local report_file="$1" check="$2" expected="$3" actual="$4"
  local pass="❌"
  if [ "$expected" = "$actual" ]; then pass="✅"; fi
  printf "| %s | %s | %s | %s |\n" "$check" "$expected" "$actual" "$pass" >> "$report_file"
}

# Source repo metadata
# shellcheck source=lib/repos.sh
. "$SYN_ROOT/scripts/bootstrap/lib/repos.sh"
