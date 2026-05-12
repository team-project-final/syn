#!/usr/bin/env bash
# learning-ai-fastapi.sh — FastAPI scaffold for learning-ai sub-project
# Sourced by phase3.sh. Requires common.sh.

###############################################################################
# learning_ai_init(repo_dir)
#   Create learning-ai/ subtree with FastAPI app + tests + CI workflow.
###############################################################################
learning_ai_init() {
  local repo_dir="$1"

  log_info "learning-ai FastAPI 초기화: $repo_dir"

  local ai_dir="$repo_dir/learning-ai"
  mkdir -p "$ai_dir/app/ai"
  mkdir -p "$ai_dir/tests"

  # --- pyproject.toml ---
  cat > "$ai_dir/pyproject.toml" <<'TOML'
[project]
name = "learning-ai"
version = "0.1.0"
description = "Synapse Learning AI — FastAPI service for AI-powered learning features"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.30.0",
    "pydantic>=2.9.0",
    "anthropic>=0.40.0",
    "openai>=1.50.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.0",
    "httpx>=0.27.0",
    "ruff>=0.7.0",
    "mypy>=1.12.0",
]

[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "SIM"]

[tool.mypy]
python_version = "3.12"
strict = true

[tool.pytest.ini_options]
testpaths = ["tests"]
TOML

  # --- app/__init__.py ---
  cat > "$ai_dir/app/__init__.py" <<'PY'
"""Synapse Learning AI — FastAPI application."""
PY

  # --- app/main.py ---
  cat > "$ai_dir/app/main.py" <<'PY'
"""Learning AI FastAPI application entry point."""

from fastapi import FastAPI

app = FastAPI(
    title="Synapse Learning AI",
    description="AI-powered learning features for Synapse",
    version="0.1.0",
)


@app.get("/health")
async def health() -> dict[str, str]:
    """Liveness probe."""
    return {"status": "ok"}


@app.get("/health/ready")
async def health_ready() -> dict[str, str]:
    """Readiness probe — checks downstream dependencies."""
    return {"status": "ready"}
PY

  # --- app/ai/__init__.py ---
  cat > "$ai_dir/app/ai/__init__.py" <<'PY'
"""AI integration modules."""
PY

  # --- tests/__init__.py ---
  cat > "$ai_dir/tests/__init__.py" <<'PY'
"""Learning AI test suite."""
PY

  # --- tests/test_health.py ---
  cat > "$ai_dir/tests/test_health.py" <<'PY'
"""Health endpoint tests."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_ready() -> None:
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}
PY

  log_ok "learning-ai FastAPI 프로젝트 생성 완료"

  # --- Overwrite CI workflow with paths-filter version ---
  local workflow_dir="$repo_dir/.github/workflows"
  mkdir -p "$workflow_dir"

  cat > "$workflow_dir/ci.yml" <<'YAML'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      java: ${{ steps.filter.outputs.java }}
      python: ${{ steps.filter.outputs.python }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            java:
              - 'learning-card/**'
              - 'build.gradle.kts'
              - 'settings.gradle.kts'
              - 'gradle/**'
            python:
              - 'learning-ai/**'

  build-java:
    needs: detect-changes
    if: needs.detect-changes.outputs.java == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: gradle/actions/setup-gradle@v4
      - name: Build & Test (Java)
        run: ./gradlew build

  build-python:
    needs: detect-changes
    if: needs.detect-changes.outputs.python == 'true'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: learning-ai
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -e '.[dev]'
      - name: Lint (ruff)
        run: ruff check .
      - name: Type check (mypy)
        run: mypy app
      - name: Test (pytest)
        run: pytest -v
YAML

  log_ok "CI workflow (paths-filter) 생성 완료"
}
