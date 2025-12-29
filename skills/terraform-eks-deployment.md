# Terraform EKS Deployment - Best Practices

## Overview
Deploying EKS clusters with Terraform requires careful handling of state, existing resources, and idempotency. This skill documents lessons learned from production deployments.

## S3 Backend for State Persistence

### Why S3 Backend?
- Local backend loses state between pipeline runs
- S3 provides persistent, shared state
- Enables team collaboration and state locking

### Configuration
```hcl
terraform {
  backend "s3" {
    bucket  = "your-terraform-state-bucket"
    key     = "project/environment/terraform.tfstate"
    region  = "us-east-1"  # S3 bucket region
    encrypt = true
  }
}
```

### Dynamic Backend in Scripts
```bash
S3_BUCKET="your-bucket"
S3_KEY="path/to/state.tfstate"

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
```

## Importing Existing Resources

### Why Import?
- IAM roles are **global** - they exist across all regions
- ECR repositories persist even after cluster deletion
- VPCs may have been created manually or by other tools

### Safe Import Function
```bash
import_if_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local import_id="$3"
    local check_cmd="$4"
    
    # Check if already in state
    if terraform state show "${resource_type}.${resource_name}" &>/dev/null; then
        echo "[SKIP] ${resource_type}.${resource_name} already in state"
        return 0
    fi
    
    # Check if exists in AWS
    if eval "${check_cmd}" &>/dev/null; then
        echo "[IMPORT] ${resource_type}.${resource_name} <- ${import_id}"
        terraform import -input=false "${resource_type}.${resource_name}" "${import_id}" || true
    else
        echo "[NEW] ${resource_type}.${resource_name} will be created"
    fi
}

# Usage examples
import_if_exists "aws_iam_role" "eks_cluster" "cluster-name-eks-cluster-role" \
    "aws iam get-role --role-name cluster-name-eks-cluster-role"

import_if_exists "aws_ecr_repository" "main" "repo-name" \
    "aws ecr describe-repositories --repository-names repo-name"

import_if_exists "aws_eks_cluster" "main" "cluster-name" \
    "aws eks describe-cluster --name cluster-name"
```

## Common EKS Deployment Errors

### 1. VpcLimitExceeded
**Error**: `The maximum number of VPCs has been reached`
**Solution**: Switch to a different region or delete unused VPCs
```bash
# Check VPC count
aws ec2 describe-vpcs --query 'length(Vpcs)'
```

### 2. EntityAlreadyExists (IAM Roles)
**Error**: `Role with name X already exists`
**Solution**: Import the role or delete it first
```bash
# Import existing role
terraform import aws_iam_role.eks_cluster cluster-name-eks-cluster-role

# Or delete (if orphaned)
aws iam delete-role --role-name old-role-name
```

### 3. InvalidParameterException (AMI)
**Error**: `Requested AMI for this version X is not supported`
**Solution**: Update `kubernetes_version` in variables
```hcl
variable "kubernetes_version" {
  default = "1.29"  # Use a supported version
}
```

### 4. RepositoryAlreadyExistsException (ECR)
**Error**: `The repository with name X already exists`
**Solution**: Import the ECR repository
```bash
terraform import aws_ecr_repository.main repo-name
```

## EKS Cluster Wait Pattern
```bash
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

case "$CLUSTER_STATUS" in
    "ACTIVE")
        echo "Cluster is ready"
        ;;
    "CREATING"|"UPDATING")
        echo "Waiting for cluster..."
        aws eks wait cluster-active --name "${CLUSTER_NAME}"
        ;;
    "NOT_FOUND")
        echo "Cluster will be created by Terraform"
        ;;
esac
```

## Recommended EKS Terraform Structure
```
terraform/aws/
├── main.tf          # VPC, EKS, Node Groups
├── variables.tf     # Input variables
├── outputs.tf       # Cluster endpoint, OIDC, etc.
├── providers.tf     # AWS and TLS providers
└── backend.tf       # S3 backend (or generated dynamically)
```

## Key Outputs to Export
```hcl
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "kubectl_config_command" {
  value = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region}"
}
```

