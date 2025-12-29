#!/bin/bash
# =============================================================================
# ArgoCD Bootstrap Script for Multi-Tenant GitOps
# =============================================================================
set -e

echo '============================================='
echo '  ArgoCD Bootstrap for Multi-Tenant GitOps'
echo '============================================='
echo ''

# Configuration
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-opsera-mcp-dev}"
AWS_REGION="${AWS_REGION:-us-west-2}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.9.3}"
REPO_URL="${REPO_URL:-https://github.com/srinivas-opsera/opsera-mcp-agents.git}"

# -----------------------------------------------------------------------------
# Configure kubectl
# -----------------------------------------------------------------------------
echo '>>> Configuring kubectl for EKS cluster...'
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"
kubectl cluster-info
echo ''

# -----------------------------------------------------------------------------
# Install ArgoCD
# -----------------------------------------------------------------------------
echo '>>> Installing ArgoCD...'
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using the official manifests
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml

echo '>>> Waiting for ArgoCD to be ready...'
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n argocd
echo 'ArgoCD is ready!'
echo ''

# -----------------------------------------------------------------------------
# Configure ArgoCD for IRSA (AWS IAM Roles for Service Accounts)
# -----------------------------------------------------------------------------
echo '>>> Configuring IRSA for ArgoCD...'

# Get the OIDC provider ARN
OIDC_PROVIDER=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ARGOCD_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EKS_CLUSTER_NAME}-argocd-role"

# Patch the argocd-server service account with the IRSA annotation
kubectl patch serviceaccount argocd-server -n argocd --type=merge -p "{\"metadata\":{\"annotations\":{\"eks.amazonaws.com/role-arn\":\"${ARGOCD_ROLE_ARN}\"}}}"
kubectl patch serviceaccount argocd-application-controller -n argocd --type=merge -p "{\"metadata\":{\"annotations\":{\"eks.amazonaws.com/role-arn\":\"${ARGOCD_ROLE_ARN}\"}}}"

echo "ArgoCD configured with IRSA role: ${ARGOCD_ROLE_ARN}"
echo ''

# -----------------------------------------------------------------------------
# Create Tenant Namespaces
# -----------------------------------------------------------------------------
echo '>>> Creating tenant namespaces...'

# Tenant A
kubectl create namespace tenant-a-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenant-a-stg --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenant-a-prod --dry-run=client -o yaml | kubectl apply -f -

# Tenant B
kubectl create namespace tenant-b-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenant-b-stg --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenant-b-prod --dry-run=client -o yaml | kubectl apply -f -

# Tenant C
kubectl create namespace tenant-c-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenant-c-stg --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tenant-c-prod --dry-run=client -o yaml | kubectl apply -f -

echo 'Tenant namespaces created!'
echo ''

# -----------------------------------------------------------------------------
# Apply ArgoCD Projects
# -----------------------------------------------------------------------------
echo '>>> Creating ArgoCD AppProjects...'
kubectl apply -f gitops/argocd/projects/

echo ''

# -----------------------------------------------------------------------------
# Apply Root App-of-Apps
# -----------------------------------------------------------------------------
echo '>>> Deploying Root App-of-Apps...'
kubectl apply -f gitops/argocd/root-app.yaml

echo ''

# -----------------------------------------------------------------------------
# Expose ArgoCD (Optional - for demo)
# -----------------------------------------------------------------------------
echo '>>> Exposing ArgoCD Server...'
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for LoadBalancer to get external IP
echo '>>> Waiting for ArgoCD LoadBalancer IP...'
sleep 30
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ArgoCD URL: https://${ARGOCD_URL}"

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo ''

echo '============================================='
echo '  ARGOCD BOOTSTRAP COMPLETE!'
echo '============================================='
echo ''
echo "ArgoCD URL: https://${ARGOCD_URL}"
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo ''
echo 'Tenant Namespaces:'
echo '  - tenant-a-dev, tenant-a-stg, tenant-a-prod'
echo '  - tenant-b-dev, tenant-b-stg, tenant-b-prod'
echo '  - tenant-c-dev, tenant-c-stg, tenant-c-prod'
echo ''
echo 'ArgoCD Apps:'
echo '  - root-app (manages all tenant apps)'
echo '  - tenant-a-apps, tenant-b-apps, tenant-c-apps (ApplicationSets)'
echo ''
echo 'Next Steps:'
echo '  1. Login to ArgoCD UI'
echo '  2. Verify all applications are synced'
echo '  3. Configure DNS for *.agent.opsera.io'
echo '============================================='

