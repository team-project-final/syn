# Polyrepo Bootstrap Scripts

`team-project-final` org에 폴리레포 8개 + 미러 + GitOps + Schema Registry
첫 스키마를 부트스트랩하는 멱등 스크립트.

## 전제

- `gh auth status` 정상
- `team-project-final` org admin 권한
- 토큰 스코프: `repo`, `workflow`, `read:org` (Phase 1 protection 실패 시 `admin:org` 추가)

## 사용

```bash
# Phase 1 — 레포 + 보호 설정 (5분)
./scripts/bootstrap/phase1.sh

# 사용자: web에서 fine-grained PAT 2개 발급 → 환경변수 export
export MIRROR_TOKEN=github_pat_xxxxx
export GITOPS_TOKEN=github_pat_xxxxx

# Phase 2 — secrets + 워크플로 (5분)
./scripts/bootstrap/phase2.sh

# Phase 3 — Hello World + 검증 (20분, Actions 대기 포함)
./scripts/bootstrap/phase3.sh
```

각 phase는 멱등이므로 재실행해도 같은 결과를 만든다. 중간 실패 시 동일 명령
재호출. 각 phase 끝에 `reports/{phase}-YYYY-MM-DD.md` 보고서가 자동 작성된다.

## 설계 근거

- 스펙: [`../../docs/superpowers/specs/2026-05-12-polyrepo-bootstrap-design.md`](../../docs/superpowers/specs/2026-05-12-polyrepo-bootstrap-design.md)
- 09 Git 규칙 v2.0 §C1 Day 1 셋업 체크리스트 실행

## 롤백

전체 무효화 명령은 스펙 §6.3 참조 (for loop 금지 — 8개 명시 명령).
