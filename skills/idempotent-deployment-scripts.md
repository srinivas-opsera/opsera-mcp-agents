# Idempotent Deployment Scripts - Best Practices

## Overview
Idempotent scripts produce the same result regardless of how many times they're run. This is critical for CI/CD pipelines where retries and re-runs are common.

## Core Principles

### 1. Check Before Creating
Always check if a resource exists before attempting to create it.

```bash
# BAD - fails on second run
kubectl create namespace my-namespace

# GOOD - idempotent
kubectl create namespace my-namespace --dry-run=client -o yaml | kubectl apply -f -
```

### 2. Use Declarative Tools
Prefer `apply` over `create`, and use tools that support desired-state reconciliation.

```bash
# BAD - imperative, fails if exists
kubectl create configmap my-config --from-literal=key=value

# GOOD - declarative, idempotent
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  key: value
EOF
```

### 3. Handle Already-Exists Errors
When declarative tools aren't available, handle errors gracefully.

```bash
# Handle AWS resource creation
aws s3 mb "s3://${BUCKET_NAME}" 2>/dev/null || true

# Better - check first
if ! aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    aws s3 mb "s3://${BUCKET_NAME}"
fi
```

## Terraform Import Pattern

```bash
import_if_exists() {
    local tf_address="$1"    # e.g., aws_iam_role.eks_cluster
    local aws_id="$2"        # e.g., role-name
    local check_cmd="$3"     # e.g., aws iam get-role --role-name X
    
    # Skip if already in state
    if terraform state show "${tf_address}" &>/dev/null; then
        echo "[SKIP] ${tf_address} already in state"
        return 0
    fi
    
    # Import if exists in AWS
    if eval "${check_cmd}" &>/dev/null; then
        echo "[IMPORT] ${tf_address}"
        terraform import -input=false "${tf_address}" "${aws_id}" 2>/dev/null || true
    else
        echo "[NEW] ${tf_address} will be created"
    fi
}

# Usage
import_if_exists "aws_iam_role.eks_cluster" \
    "my-eks-cluster-role" \
    "aws iam get-role --role-name my-eks-cluster-role"
```

## Tool Installation Pattern

```bash
# Idempotent tool installation
install_if_missing() {
    local cmd="$1"
    local install_fn="$2"
    
    if command -v "$cmd" &>/dev/null; then
        echo "$cmd already installed: $(command -v $cmd)"
    else
        echo "Installing $cmd..."
        eval "$install_fn"
    fi
}

# Terraform
install_if_missing "terraform" '
    cd /tmp
    wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
    unzip -o -q terraform_1.6.0_linux_amd64.zip
    mv terraform /usr/local/bin/
    rm -f terraform_1.6.0_linux_amd64.zip
'

# kubectl
install_if_missing "kubectl" '
    curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
'

# AWS CLI
install_if_missing "aws" '
    apt-get update -qq && apt-get install -y -qq awscli
'
```

## Kubernetes Resource Patterns

### Namespace
```bash
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -
```

### ConfigMap from File
```bash
kubectl create configmap $NAME --from-file=$FILE \
    --dry-run=client -o yaml | kubectl apply -f -
```

### Secret
```bash
kubectl create secret generic $NAME --from-literal=key=$VALUE \
    --dry-run=client -o yaml | kubectl apply -f -
```

### Service Patching
```bash
# Only patch if needed
CURRENT_TYPE=$(kubectl get svc $SVC -o jsonpath='{.spec.type}')
if [ "$CURRENT_TYPE" != "LoadBalancer" ]; then
    kubectl patch svc $SVC -p '{"spec": {"type": "LoadBalancer"}}'
fi
```

## AWS Resource Patterns

### S3 Bucket
```bash
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    aws s3 mb "s3://${BUCKET}" --region $REGION
    aws s3api put-bucket-versioning --bucket "$BUCKET" \
        --versioning-configuration Status=Enabled
fi
```

### IAM Role
```bash
if ! aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    aws iam create-role --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://trust-policy.json
fi
```

### EKS Cluster Wait
```bash
STATUS=$(aws eks describe-cluster --name "$CLUSTER" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

case "$STATUS" in
    "ACTIVE")     echo "Cluster ready" ;;
    "CREATING")   aws eks wait cluster-active --name "$CLUSTER" ;;
    "NOT_FOUND")  echo "Cluster needs creation" ;;
esac
```

## Non-Interactive Flags

| Tool | Flag | Purpose |
|------|------|---------|
| `unzip` | `-o` | Overwrite without prompting |
| `apt-get` | `-y -qq` | Yes to all, quiet |
| `terraform` | `-input=false` | No interactive prompts |
| `terraform` | `-auto-approve` | Skip confirmation |
| `npm/npx` | `--yes` | Accept defaults |
| `curl` | `-sS` | Silent but show errors |
| `wget` | `-q` | Quiet mode |

## Complete Idempotent Script Template

```bash
#!/bin/bash
set -e  # Exit on error

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-my-cluster}"
REGION="${REGION:-us-west-2}"

# Validate prerequisites
check_prerequisites() {
    [ -z "$AWS_ACCESS_KEY_ID" ] && { echo "ERROR: AWS_ACCESS_KEY_ID not set"; exit 1; }
    [ -z "$AWS_SECRET_ACCESS_KEY" ] && { echo "ERROR: AWS_SECRET_ACCESS_KEY not set"; exit 1; }
}

# Install tools (idempotent)
install_tools() {
    command -v terraform &>/dev/null || install_terraform
    command -v kubectl &>/dev/null || install_kubectl
    command -v aws &>/dev/null || install_awscli
}

# Check/wait for resources
wait_for_cluster() {
    local status=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
        --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    case "$status" in
        "ACTIVE") return 0 ;;
        "CREATING"|"UPDATING") 
            aws eks wait cluster-active --name "$CLUSTER_NAME" ;;
        *) return 1 ;;
    esac
}

# Main
main() {
    check_prerequisites
    install_tools
    
    if wait_for_cluster; then
        echo "Cluster exists, configuring..."
        aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
    else
        echo "Cluster needs creation..."
        # Run Terraform
    fi
    
    # Deploy apps (idempotent kubectl apply)
    kubectl apply -f manifests/
}

main "$@"
```

