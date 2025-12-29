#!/bin/bash
# =============================================================================
# Full EKS + ArgoCD Multi-Tenant Deployment
# This script is IDEMPOTENT - safe to run multiple times
# =============================================================================
set -e

echo '============================================='
echo '  Full EKS + ArgoCD Deployment'
echo '  Version: 1.0'
echo '============================================='
echo ''

# -----------------------------------------------------------------------------
# Configuration (can be overridden via environment variables)
# -----------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-opsera-mcp-dev}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.9.3}"
REPO_URL="${REPO_URL:-https://github.com/srinivas-opsera/opsera-mcp-agents.git}"
S3_BUCKET="${S3_BUCKET:-opsera-agentic-s3-v1}"
S3_KEY="${S3_KEY:-opsera-mcp-agents/eks-terraform.tfstate}"

# Check AWS credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERROR: AWS credentials not set!"
    echo "Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    exit 1
fi

export AWS_DEFAULT_REGION="${AWS_REGION}"
export AWS_REGION="${AWS_REGION}"

echo "Configuration:"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Region:      ${AWS_REGION}"
echo "  ArgoCD:      ${ARGOCD_VERSION}"
echo "  S3 Backend:  s3://${S3_BUCKET}/${S3_KEY}"
echo ''

# -----------------------------------------------------------------------------
# PHASE 1: EKS Infrastructure (Terraform)
# -----------------------------------------------------------------------------
echo '============================================='
echo '  PHASE 1: EKS Infrastructure'
echo '============================================='

# Check if EKS cluster already exists
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
echo "Current EKS status: ${CLUSTER_STATUS}"

if [ "${CLUSTER_STATUS}" == "ACTIVE" ]; then
    echo "✅ EKS cluster already exists and is ACTIVE"
    echo "   Skipping Terraform (cluster exists)"
else
    echo ">>> EKS cluster needs to be created via Terraform"
    echo "   Run: ./scripts/eks-deploy-simple.sh"
    echo "   Or run the eks-deploy-simple-v1 pipeline"
    
    # If running full deploy, prompt or auto-run terraform
    if [ "${AUTO_TERRAFORM:-false}" == "true" ]; then
        echo ">>> Running Terraform..."
        cd terraform/aws
        
        # Create backend override
        cat > backend_override.tf << EOF
terraform {
  backend "s3" {
    bucket  = "${S3_BUCKET}"
    key     = "${S3_KEY}"
    region  = "us-east-1"
    encrypt = true
  }
}
EOF
        terraform init -input=false -reconfigure
        terraform apply -auto-approve -input=false
        cd ../..
    fi
fi
echo ''

# Wait for cluster if creating
if [ "${CLUSTER_STATUS}" == "CREATING" ]; then
    echo ">>> Waiting for EKS cluster to become ACTIVE..."
    aws eks wait cluster-active --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
fi

# -----------------------------------------------------------------------------
# PHASE 2: Configure kubectl
# -----------------------------------------------------------------------------
echo '============================================='
echo '  PHASE 2: Configure kubectl'
echo '============================================='

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
kubectl cluster-info
echo ''

# -----------------------------------------------------------------------------
# PHASE 3: Install ArgoCD
# -----------------------------------------------------------------------------
echo '============================================='
echo '  PHASE 3: Install ArgoCD'
echo '============================================='

# Check if ArgoCD is already installed
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo "✅ ArgoCD already installed"
else
    echo ">>> Installing ArgoCD ${ARGOCD_VERSION}..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    
    echo ">>> Waiting for ArgoCD pods..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
fi

echo "ArgoCD pods:"
kubectl get pods -n argocd --no-headers | head -5
echo ''

# -----------------------------------------------------------------------------
# PHASE 4: Create Tenant Namespaces
# -----------------------------------------------------------------------------
echo '============================================='
echo '  PHASE 4: Tenant Namespaces'
echo '============================================='

for tenant in a b c; do
    for env in dev stg prod; do
        kubectl create namespace tenant-${tenant}-${env} --dry-run=client -o yaml | kubectl apply -f -
    done
done

echo "Tenant namespaces:"
kubectl get ns | grep tenant || echo "(none)"
echo ''

# -----------------------------------------------------------------------------
# PHASE 5: Deploy GitOps Apps
# -----------------------------------------------------------------------------
echo '============================================='
echo '  PHASE 5: Deploy GitOps Apps'
echo '============================================='

# Apply ArgoCD Projects
echo ">>> Applying ArgoCD Projects..."
kubectl apply -f gitops/argocd/projects/

# Apply Root App-of-Apps
echo ">>> Deploying Root App-of-Apps..."
kubectl apply -f gitops/argocd/root-app.yaml

echo "ArgoCD Applications:"
kubectl get applications -n argocd --no-headers 2>/dev/null || echo "(syncing...)"
echo ''

# -----------------------------------------------------------------------------
# PHASE 6: Expose ArgoCD
# -----------------------------------------------------------------------------
echo '============================================='
echo '  PHASE 6: Expose ArgoCD'
echo '============================================='

# Patch to LoadBalancer if not already
SVC_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
if [ "$SVC_TYPE" != "LoadBalancer" ]; then
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
fi

# Get URL
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "pending")

echo ''
echo '============================================='
echo '  DEPLOYMENT COMPLETE!'
echo '============================================='
echo ''
echo "ArgoCD URL:      https://${ARGOCD_URL}"
echo "ArgoCD User:     admin"
echo "ArgoCD Password: ${ARGOCD_PASSWORD}"
echo ''
echo "Tenant Namespaces:"
echo "  tenant-a-dev, tenant-a-stg, tenant-a-prod"
echo "  tenant-b-dev, tenant-b-stg, tenant-b-prod"  
echo "  tenant-c-dev, tenant-c-stg, tenant-c-prod"
echo ''
echo "To re-run this script: ./scripts/full-deploy.sh"
echo '============================================='

