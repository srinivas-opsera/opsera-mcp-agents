# Skill: Writing Idempotent Deployment Scripts

## Overview
Idempotent scripts produce the same result regardless of how many times they're run. Essential for reliable CI/CD pipelines.

## Key Learnings

### 1. Idempotent Namespace Creation

```bash
# ❌ NOT idempotent - fails on second run
kubectl create namespace my-namespace

# ✅ Idempotent - works every time
kubectl create namespace my-namespace --dry-run=client -o yaml | kubectl apply -f -
```

### 2. Idempotent Resource Application

```bash
# ❌ NOT idempotent - creates duplicates
kubectl create -f manifest.yaml

# ✅ Idempotent - creates or updates
kubectl apply -f manifest.yaml
```

### 3. Idempotent Tool Installation

```bash
# ✅ Check if tool exists before installing
if ! command -v terraform &>/dev/null; then
    echo "Installing Terraform..."
    wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
    unzip -o -q terraform_1.6.0_linux_amd64.zip -d /tmp
    mv /tmp/terraform /usr/local/bin/
fi
terraform version
```

### 4. Idempotent Terraform Import

```bash
import_if_exists() {
    local resource="$1"
    local import_id="$2"
    local check_cmd="$3"
    
    # Skip if already in state
    if terraform state show "$resource" &>/dev/null; then
        echo "[SKIP] $resource already in state"
        return 0
    fi
    
    # Import if exists in cloud
    if eval "$check_cmd" &>/dev/null; then
        echo "[IMPORT] $resource <- $import_id"
        terraform import -input=false "$resource" "$import_id" || true
    else
        echo "[NEW] $resource will be created"
    fi
}

# Usage
import_if_exists "aws_iam_role.eks_cluster" "my-eks-role" \
    "aws iam get-role --role-name my-eks-role"
```

### 5. Idempotent S3 Bucket Creation

```bash
# ✅ Create bucket only if it doesn't exist
BUCKET_NAME="my-terraform-state"
if ! aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Bucket exists"
else
    echo "Creating bucket..."
    aws s3 mb "s3://${BUCKET_NAME}" --region us-east-1
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
fi
```

### 6. Idempotent EKS Cluster Wait

```bash
CLUSTER_NAME="my-cluster"
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

case "$CLUSTER_STATUS" in
    "ACTIVE")
        echo "Cluster is ACTIVE"
        ;;
    "CREATING")
        echo "Waiting for cluster to become ACTIVE..."
        aws eks wait cluster-active --name "${CLUSTER_NAME}"
        ;;
    "NOT_FOUND")
        echo "Cluster not found - will create"
        ;;
    *)
        echo "Cluster in unexpected state: ${CLUSTER_STATUS}"
        exit 1
        ;;
esac
```

### 7. Idempotent Service Patching

```bash
# ✅ Only patch if needed
CURRENT_TYPE=$(kubectl get svc argocd-server -n argocd \
    -o jsonpath='{.spec.type}' 2>/dev/null || echo "NotFound")

if [ "$CURRENT_TYPE" != "LoadBalancer" ]; then
    kubectl patch svc argocd-server -n argocd \
        -p '{"spec": {"type": "LoadBalancer"}}'
fi
```

### 8. Idempotent File Creation

```bash
# ✅ Overwrite or create file
cat > config.yaml << EOF
key: value
environment: production
EOF

# ✅ Append only if not present
grep -q "my-config" ~/.bashrc || echo "export MY_CONFIG=value" >> ~/.bashrc
```

### 9. Complete Idempotent Deployment Script

```bash
#!/bin/bash
# full-deploy.sh - Fully idempotent deployment script
set -e

CLUSTER_NAME="${CLUSTER_NAME:-my-cluster}"
REGION="${AWS_REGION:-us-west-2}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.9.3}"

echo "============================================="
echo "  Idempotent Deployment Script"
echo "============================================="

# Phase 1: Check prerequisites
echo ">>> Checking prerequisites..."
command -v aws >/dev/null || { echo "AWS CLI required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl required"; exit 1; }

# Phase 2: Check/wait for EKS cluster
echo ">>> Checking EKS cluster..."
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo "  Cluster is ACTIVE"
elif [ "$CLUSTER_STATUS" == "CREATING" ]; then
    echo "  Waiting for cluster..."
    aws eks wait cluster-active --name "${CLUSTER_NAME}"
else
    echo "  Cluster not found or in bad state: ${CLUSTER_STATUS}"
    exit 1
fi

# Phase 3: Configure kubectl
echo ">>> Configuring kubectl..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

# Phase 4: Install ArgoCD (idempotent)
echo ">>> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    kubectl apply -n argocd -f \
        https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n argocd
else
    echo "  ArgoCD already installed"
fi

# Phase 5: Create namespaces (idempotent)
echo ">>> Creating namespaces..."
for tenant in a b c; do
    for env in dev stg prod; do
        kubectl create namespace tenant-${tenant}-${env} \
            --dry-run=client -o yaml | kubectl apply -f -
    done
done

# Phase 6: Apply GitOps apps (idempotent)
echo ">>> Applying GitOps configuration..."
kubectl apply -f gitops/argocd/projects/
kubectl apply -f gitops/argocd/root-app.yaml

# Phase 7: Expose ArgoCD (idempotent)
echo ">>> Exposing ArgoCD..."
SVC_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
if [ "$SVC_TYPE" != "LoadBalancer" ]; then
    kubectl patch svc argocd-server -n argocd \
        -p '{"spec": {"type": "LoadBalancer"}}'
fi

# Phase 8: Output results
echo ""
echo "============================================="
echo "  DEPLOYMENT COMPLETE"
echo "============================================="
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "pending")

echo "ArgoCD URL:      https://${ARGOCD_URL}"
echo "ArgoCD Password: ${ARGOCD_PASS}"
echo ""
echo "This script is idempotent - safe to run again!"
```

## Principles

1. **Check before create** - Always check if resource exists
2. **Use declarative tools** - `kubectl apply` over `kubectl create`
3. **Use `--dry-run=client -o yaml | apply`** for imperative commands
4. **Handle all states** - ACTIVE, CREATING, NOT_FOUND, etc.
5. **Use || true** for optional imports that may fail
6. **Test by running twice** - Should succeed both times

## Anti-Patterns

```bash
# ❌ Fails on second run
kubectl create namespace foo

# ❌ Creates duplicates
kubectl create -f deployment.yaml

# ❌ Doesn't check for existing resources
terraform apply  # Without import

# ❌ Hardcoded paths that may not exist
cd /some/path/that/may/not/exist
```

