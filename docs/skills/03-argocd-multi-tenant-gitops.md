# Skill: ArgoCD Multi-Tenant GitOps Setup

## Overview
Setting up ArgoCD for multi-tenant environments using the App-of-Apps pattern with ApplicationSets.

## Key Learnings

### 1. ArgoCD Installation on EKS

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD (use specific version for reproducibility)
ARGOCD_VERSION="v2.9.3"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n argocd

# Expose via LoadBalancer (for demo/dev)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get credentials
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "URL: https://${ARGOCD_URL}"
echo "User: admin"
echo "Password: ${ARGOCD_PASSWORD}"
```

### 2. App-of-Apps Pattern

The root application manages all other applications:

```yaml
# gitops/argocd/root-app.yaml
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
    path: gitops/apps  # Contains ApplicationSets
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

### 3. AppProjects for Tenant Isolation

Each tenant gets its own AppProject with restricted access:

```yaml
# gitops/argocd/projects/tenant-a.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: tenant-a
  namespace: argocd
spec:
  description: "Tenant A - Multi-environment project"
  
  # Allowed source repositories
  sourceRepos:
    - "https://github.com/your-org/*"
  
  # Allowed destination namespaces
  destinations:
    - namespace: tenant-a-dev
      server: https://kubernetes.default.svc
    - namespace: tenant-a-stg
      server: https://kubernetes.default.svc
    - namespace: tenant-a-prod
      server: https://kubernetes.default.svc
  
  # Allowed cluster resources
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: networking.k8s.io
      kind: Ingress
  
  # Namespace resources (allow all within allowed namespaces)
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  
  # RBAC roles
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

### 4. ApplicationSets for Dynamic App Generation

Generate apps automatically for each tenant/environment:

```yaml
# gitops/apps/tenant-a-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-a-apps
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          # Apps
          - list:
              elements:
                - app: app-a1
                - app: app-a2
                - app: app-a3
          # Environments
          - list:
              elements:
                - env: dev
                  namespace: tenant-a-dev
                - env: stg
                  namespace: tenant-a-stg
  
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

### 5. Kustomize Overlays for Environments

Base template:
```yaml
# gitops/tenants/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app
    spec:
      containers:
        - name: app
          image: nginx:alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
```

Environment overlay:
```yaml
# gitops/tenants/tenant-a/dev/app-a1/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: tenant-a-dev
resources:
  - ../../../base

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

configMapGenerator:
  - name: app-config
    literals:
      - ENVIRONMENT=dev
      - TENANT=tenant-a
```

### 6. IRSA for ArgoCD

Configure ArgoCD with IAM Roles for Service Accounts:

```bash
# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ARGOCD_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-argocd-role"

# Patch service accounts
kubectl patch serviceaccount argocd-server -n argocd --type=merge \
  -p "{\"metadata\":{\"annotations\":{\"eks.amazonaws.com/role-arn\":\"${ARGOCD_ROLE_ARN}\"}}}"

kubectl patch serviceaccount argocd-application-controller -n argocd --type=merge \
  -p "{\"metadata\":{\"annotations\":{\"eks.amazonaws.com/role-arn\":\"${ARGOCD_ROLE_ARN}\"}}}"
```

### 7. Tenant Namespace Structure

Create namespaces for each tenant/environment:

```bash
# Create all tenant namespaces
for tenant in a b c; do
  for env in dev stg prod; do
    kubectl create namespace tenant-${tenant}-${env} --dry-run=client -o yaml | kubectl apply -f -
  done
done
```

## Directory Structure

```
gitops/
├── argocd/
│   ├── root-app.yaml           # Root App-of-Apps
│   └── projects/
│       ├── tenant-a.yaml       # Tenant A AppProject
│       ├── tenant-b.yaml       # Tenant B AppProject
│       └── tenant-c.yaml       # Tenant C AppProject
├── apps/
│   ├── tenant-a-apps.yaml      # ApplicationSet for Tenant A
│   ├── tenant-b-apps.yaml      # ApplicationSet for Tenant B
│   └── tenant-c-apps.yaml      # ApplicationSet for Tenant C
└── tenants/
    ├── base/                   # Shared Kustomize base
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    ├── tenant-a/
    │   ├── dev/
    │   │   ├── app-a1/kustomization.yaml
    │   │   └── app-a2/kustomization.yaml
    │   └── stg/
    │       ├── app-a1/kustomization.yaml
    │       └── app-a2/kustomization.yaml
    └── tenant-b/
        └── ...
```

## Best Practices

1. **Use App-of-Apps** for managing multiple applications
2. **Use AppProjects** for tenant isolation
3. **Use ApplicationSets** for dynamic app generation
4. **Use Kustomize overlays** for environment-specific configs
5. **Enable auto-sync** with prune and self-heal
6. **Use IRSA** for AWS integrations
7. **Expose via Ingress** (not LoadBalancer) in production
8. **Rotate initial admin password** after first login

