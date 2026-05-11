#!/usr/bin/env bash
# repos.sh — Repository metadata for 8 polyrepo entries.

# Tier 1 public service repos (6)
TIER1_REPOS=(
  "synapse-platform-svc|public|Synapse — platform services (auth/audit/billing/notification)|synapse,auth,billing,spring-boot,java"
  "synapse-engagement-svc|public|Synapse — engagement services (community/gamification)|synapse,community,gamification,spring-boot,java"
  "synapse-knowledge-svc|public|Synapse — knowledge services (note/graph/chunking)|synapse,pkm,graph,spring-boot,java"
  "synapse-learning-svc|public|Synapse — learning services (card/srs Java + ai Python)|synapse,srs,ai,spring-boot,fastapi"
  "synapse-frontend|public|Synapse — Flutter frontend (web/mobile)|synapse,flutter,riverpod,go-router"
  "synapse-shared|public|Synapse — shared Avro schemas + common library|synapse,avro,schema-registry,kafka"
)

# Tier 2 mirror (1)
MIRROR_REPO="synapse-mirror|private|Synapse — auto-synced read-only mirror of all Tier 1 service repos|synapse,mirror"

# Tier 3 gitops (1)
GITOPS_REPO="synapse-gitops|private|Synapse — Kubernetes manifests + ArgoCD ApplicationSet|synapse,gitops,kubernetes,argocd"

# All repo names (for iteration)
ALL_REPO_NAMES=(
  "synapse-platform-svc"
  "synapse-engagement-svc"
  "synapse-knowledge-svc"
  "synapse-learning-svc"
  "synapse-frontend"
  "synapse-shared"
  "synapse-mirror"
  "synapse-gitops"
)

# Tier 1 names only (those that need MIRROR_TOKEN/GITOPS_TOKEN secrets)
TIER1_NAMES=(
  "synapse-platform-svc"
  "synapse-engagement-svc"
  "synapse-knowledge-svc"
  "synapse-learning-svc"
  "synapse-frontend"
  "synapse-shared"
)

# Java backend repos (Spring Boot 4)
JAVA_BACKEND_NAMES=(
  "synapse-platform-svc"
  "synapse-engagement-svc"
  "synapse-knowledge-svc"
)
# learning-svc 는 multi-module (Java + Python) 이라 별도 처리

# Service name → Spring Modulith module list
declare -A MODULES
MODULES["synapse-platform-svc"]="auth audit billing notification"
MODULES["synapse-engagement-svc"]="community gamification"
MODULES["synapse-knowledge-svc"]="note graph chunking"
