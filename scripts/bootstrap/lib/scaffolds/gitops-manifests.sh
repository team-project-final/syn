#!/usr/bin/env bash
# gitops-manifests.sh — Kubernetes manifest scaffold for synapse-gitops
# Sourced by phase3.sh. Requires common.sh.

###############################################################################
# gitops_init(repo_dir)
#   Create ArgoCD ApplicationSet, Kustomize overlays, infra stubs.
###############################################################################
gitops_init() {
  local repo_dir="$1"

  log_info "synapse-gitops 매니페스트 초기화: $repo_dir"

  local services=("platform-svc" "engagement-svc" "knowledge-svc" "learning-card" "learning-ai")
  local envs=("dev" "staging" "prod")

  # --- infra dirs with .gitkeep ---
  for infra_dir in istio monitoring ingress external-secrets; do
    mkdir -p "$repo_dir/infra/$infra_dir"
    touch "$repo_dir/infra/$infra_dir/.gitkeep"
  done

  # --- ArgoCD ApplicationSet ---
  mkdir -p "$repo_dir/argocd"

  cat > "$repo_dir/argocd/applicationset.yaml" <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-apps
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - service: platform-svc
                - service: engagement-svc
                - service: knowledge-svc
                - service: learning-card
                - service: learning-ai
          - list:
              elements:
                - env: dev
                - env: staging
                - env: prod
  template:
    metadata:
      name: "synapse-{{service}}-{{env}}"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: synapse
        app.kubernetes.io/component: "{{service}}"
        environment: "{{env}}"
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{service}}/overlays/{{env}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "synapse-{{env}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  templatePatch: |
    {{- if ne env "dev" }}
    spec:
      syncPolicy:
        automated: null
    {{- end }}
YAML

  # --- ArgoCD Project ---
  cat > "$repo_dir/argocd/projects.yaml" <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: synapse
  namespace: argocd
spec:
  description: Synapse application project
  sourceRepos:
    - https://github.com/team-project-final/synapse-gitops.git
  destinations:
    - namespace: "synapse-*"
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
YAML

  # --- RELEASE_NOTES.md ---
  cat > "$repo_dir/RELEASE_NOTES.md" <<'MD'
# Release Notes

## v0.0.0 — Bootstrap

- Initial GitOps repository structure
- ArgoCD ApplicationSet for 5 services × 3 environments
- Kustomize base + overlay structure
- Infrastructure stubs (istio, monitoring, ingress, external-secrets)
MD

  # --- Per-service manifests ---
  for svc in "${services[@]}"; do
    local base_dir="$repo_dir/apps/$svc/base"
    mkdir -p "$base_dir"

    # Health check paths — learning-ai uses FastAPI endpoints
    local liveness_path="/actuator/health/liveness"
    local readiness_path="/actuator/health/readiness"
    local container_port="8080"

    if [ "$svc" = "learning-ai" ]; then
      liveness_path="/health"
      readiness_path="/health/ready"
      container_port="8000"
    fi

    # deployment.yaml
    cat > "$base_dir/deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${svc}
  labels:
    app.kubernetes.io/name: ${svc}
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${svc}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${svc}
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: ${svc}
          image: ghcr.io/team-project-final/synapse-${svc}:latest
          ports:
            - containerPort: ${container_port}
          livenessProbe:
            httpGet:
              path: ${liveness_path}
              port: ${container_port}
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: ${readiness_path}
              port: ${container_port}
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
YAML

    # service.yaml
    local svc_port="80"
    local target_port="$container_port"

    cat > "$base_dir/service.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: ${svc}
  labels:
    app.kubernetes.io/name: ${svc}
    app.kubernetes.io/part-of: synapse
spec:
  type: ClusterIP
  ports:
    - port: ${svc_port}
      targetPort: ${target_port}
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: ${svc}
YAML

    # kustomization.yaml (base)
    cat > "$base_dir/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
YAML

    # overlays per env
    for env in "${envs[@]}"; do
      local overlay_dir="$repo_dir/apps/$svc/overlays/$env"
      mkdir -p "$overlay_dir"

      local replica_count=1
      case "$env" in
        staging) replica_count=2 ;;
        prod) replica_count=3 ;;
      esac

      cat > "$overlay_dir/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-${env}

patches:
  - target:
      kind: Deployment
      name: ${svc}
    patch: |
      - op: replace
        path: /spec/replicas
        value: ${replica_count}

images:
  - name: ghcr.io/team-project-final/synapse-${svc}
    newTag: ${env}-latest
YAML
    done

    log_ok "서비스 매니페스트 생성 완료: $svc"
  done

  log_ok "synapse-gitops 매니페스트 초기화 완료"
}
