# ArgoCD Multi-Tenant GitOps Architecture

## Overview
This skill documents how to set up a multi-tenant GitOps architecture using ArgoCD with the App-of-Apps pattern, ApplicationSets, and proper tenant isolation.

## Architecture Pattern

```
                    ┌─────────────────┐
                    │    root-app     │
                    │  (App-of-Apps)  │
                    └────────┬────────┘
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
   ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
   │ tenant-a-apps │ │ tenant-b-apps │ │ tenant-c-apps │
   │(ApplicationSet)│ │(ApplicationSet)│ │(ApplicationSet)│
   └───────┬───────┘ └───────┬───────┘ └───────┬───────┘
           │                 │                 │
     ┌─────┴─────┐     ┌─────┴─────┐     ┌─────┴─────┐
     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼
   dev   stg   prod   dev   stg   prod   dev   stg   prod
```

## Directory Structure

```
gitops/
├── argocd/
│   ├── namespace.yaml
│   ├── root-app.yaml           # Root App-of-Apps
│   └── projects/
│       ├── tenant-a.yaml       # AppProject for Tenant A
│       ├── tenant-b.yaml       # AppProject for Tenant B
│       └── tenant-c.yaml       # AppProject for Tenant C
├── apps/
│   ├── tenant-a-apps.yaml      # ApplicationSet for Tenant A
│   ├── tenant-b-apps.yaml      # ApplicationSet for Tenant B
│   └── tenant-c-apps.yaml      # ApplicationSet for Tenant C
└── tenants/
    ├── base/                   # Shared Kustomize base
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   └── kustomization.yaml
    ├── tenant-a/
    │   ├── dev/app-a1/kustomization.yaml
    │   ├── dev/app-a2/kustomization.yaml
    │   ├── stg/app-a1/kustomization.yaml
    │   └── stg/app-a2/kustomization.yaml
    ├── tenant-b/
    │   └── ...
    └── tenant-c/
        └── ...
```

## AppProject for Tenant Isolation

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: tenant-a
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: "Tenant A - Multi-environment project"
  
  # Allowed source repositories
  sourceRepos:
    - "https://github.com/your-org/your-repo.git"
  
  # Allowed destination clusters and namespaces
  destinations:
    - namespace: tenant-a-dev
      server: https://kubernetes.default.svc
    - namespace: tenant-a-stg
      server: https://kubernetes.default.svc
    - namespace: tenant-a-prod
      server: https://kubernetes.default.svc
  
  # Allowed cluster-scoped resources
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: networking.k8s.io
      kind: Ingress
  
  # RBAC roles within the project
  roles:
    - name: admin
      policies:
        - p, proj:tenant-a:admin, applications, *, tenant-a/*, allow
      groups:
        - tenant-a-admins
    - name: developer
      policies:
        - p, proj:tenant-a:developer, applications, get, tenant-a/*, allow
        - p, proj:tenant-a:developer, applications, sync, tenant-a/*, allow
      groups:
        - tenant-a-developers
```

## ApplicationSet with Matrix Generator

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-a-apps
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          # Apps for this tenant
          - list:
              elements:
                - app: app-a1
                  port: 8080
                - app: app-a2
                  port: 8081
                - app: app-a3
                  port: 8082
          # Environments
          - list:
              elements:
                - env: dev
                  namespace: tenant-a-dev
                  replicas: 1
                - env: stg
                  namespace: tenant-a-stg
                  replicas: 2
  
  template:
    metadata:
      name: 'tenant-a-{{app}}-{{env}}'
      namespace: argocd
      labels:
        tenant: tenant-a
        app: '{{app}}'
        environment: '{{env}}'
    spec:
      project: tenant-a
      
      source:
        repoURL: https://github.com/your-org/your-repo.git
        targetRevision: main
        path: 'gitops/tenants/tenant-a/{{env}}/{{app}}'
        
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

## Root App-of-Apps

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: https://github.com/your-org/your-repo.git
    targetRevision: main
    path: gitops/apps  # Contains all ApplicationSets
  
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Kustomize Overlay Example

```yaml
# gitops/tenants/tenant-a/dev/app-a1/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: tenant-a-dev

resources:
  - ../../../base  # Shared base templates

namePrefix: app-a1-

commonLabels:
  tenant: tenant-a
  app: app-a1
  environment: dev

patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
    target:
      kind: Deployment
      name: app
  - patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: app-a1-dev.agent.opsera.io
    target:
      kind: Ingress
      name: app

configMapGenerator:
  - name: app-config
    literals:
      - ENVIRONMENT=dev
      - TENANT=tenant-a
      - APP_NAME=app-a1
```

## ArgoCD Installation on EKS

```bash
# Install ArgoCD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml

# Wait for pods
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Expose via LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## IRSA for ArgoCD (AWS)

```bash
# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME \
    --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

# Annotate service accounts
kubectl patch serviceaccount argocd-server -n argocd --type=merge \
    -p '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::ACCOUNT:role/argocd-role"}}}'
```

## Tenant Namespace Creation (Idempotent)

```bash
for tenant in a b c; do
    for env in dev stg prod; do
        kubectl create namespace tenant-${tenant}-${env} \
            --dry-run=client -o yaml | kubectl apply -f -
    done
done
```

## Benefits of This Architecture

1. **Tenant Isolation**: Each tenant has its own AppProject with restricted namespaces
2. **DRY Configuration**: Shared base with environment-specific overlays
3. **Automated Deployment**: ApplicationSets auto-generate apps for each tenant/environment
4. **Self-Healing**: ArgoCD automatically reconciles drift
5. **Audit Trail**: All changes tracked in Git
6. **Scalable**: Add new tenants/apps by adding YAML files

