# EKS Terraform Deployment Patterns

## Overview
Deploying EKS with Terraform requires careful handling of state management, resource dependencies, and idempotency.

## Key Learnings

### 1. IAM Roles are Global (Not Regional!)

IAM roles exist globally in AWS, not per-region. This causes conflicts when:
- Running Terraform in different regions
- Re-running Terraform without proper state

```bash
# Error when role already exists
Error: EntityAlreadyExists: Role with name opsera-mcp-dev-eks-cluster-role already exists
```

**Solution:** Import existing roles before applying:

```bash
# Check if role exists
if aws iam get-role --role-name ${CLUSTER_NAME}-eks-cluster-role &>/dev/null; then
    terraform import aws_iam_role.eks_cluster ${CLUSTER_NAME}-eks-cluster-role
fi
```

### 2. State Management is Critical

Without proper state management, Terraform will:
- Try to create resources that already exist
- Fail with "already exists" errors
- Or worse, create duplicate resources

**Always use remote state:**

```hcl
terraform {
  backend "s3" {
    bucket  = "your-terraform-state-bucket"
    key     = "project/eks/terraform.tfstate"
    region  = "us-east-1"  # State bucket region (can differ from resources)
    encrypt = true
    # Optional: DynamoDB for state locking
    # dynamodb_table = "terraform-locks"
  }
}
```

### 3. Idempotent Import Script Pattern

```bash
#!/bin/bash
# Function to safely import a resource
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
import_if_exists "aws_iam_role" "eks_cluster" "${CLUSTER_NAME}-eks-cluster-role" \
    "aws iam get-role --role-name ${CLUSTER_NAME}-eks-cluster-role"

import_if_exists "aws_ecr_repository" "main" "my-repo" \
    "aws ecr describe-repositories --repository-names my-repo"

import_if_exists "aws_vpc" "main" "${VPC_ID}" \
    "aws ec2 describe-vpcs --vpc-ids ${VPC_ID}"
```

### 4. EKS Version and AMI Compatibility

EKS node groups require specific AMIs for each Kubernetes version:

```bash
# Error when AMI not available
InvalidParameterException: Requested AMI for this version 1.28 is not supported
```

**Check AMI availability before deploying:**

```bash
# Check available EKS-optimized AMIs
aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/1.29/amazon-linux-2/recommended/image_id \
  --region us-west-2 \
  --query 'Parameter.Value' --output text
```

**Use stable Kubernetes versions:**
- 1.29 ✅ (current stable)
- 1.28 ⚠️ (may have AMI issues in some regions)
- 1.27 ✅ (stable)

### 5. VPC Limits

AWS has default VPC limits per region:

```bash
# Error when limit reached
VpcLimitExceeded: The maximum number of VPCs has been reached.
```

**Solutions:**
1. Clean up unused VPCs
2. Request limit increase via AWS Support
3. Use a different region

### 6. EKS Cluster Creation Time

EKS clusters take 10-15 minutes to create. Use wait commands:

```bash
# Wait for cluster to become active
aws eks wait cluster-active --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Check cluster status
CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${CLUSTER_STATUS}" == "CREATING" ]; then
    echo "Waiting for cluster..."
    aws eks wait cluster-active --name ${CLUSTER_NAME}
fi
```

### 7. Complete EKS Terraform Module Structure

```
terraform/aws/
├── main.tf           # EKS, VPC, IAM, ECR resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── providers.tf      # AWS and TLS providers
├── backend.tf        # S3 backend configuration
└── versions.tf       # Required provider versions
```

**Minimal variables.tf:**

```hcl
variable "cluster_name" {
  default = "my-eks-cluster"
}

variable "aws_region" {
  default = "us-west-2"
}

variable "kubernetes_version" {
  default = "1.29"  # Use stable versions
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "instance_type" {
  default = "t3.medium"
}

variable "desired_size" {
  default = 2
}
```

### 8. OIDC Provider for IRSA

EKS requires an OIDC provider for IAM Roles for Service Accounts (IRSA):

```hcl
# Get OIDC certificate thumbprint
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Create OIDC provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# IRSA role for a service account
resource "aws_iam_role" "app_role" {
  name = "${var.cluster_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:my-namespace:my-service-account"
        }
      }
    }]
  })
}
```

### 9. Output Essential Values

```hcl
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "kubectl_config_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}
```

