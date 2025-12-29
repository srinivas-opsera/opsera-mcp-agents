# Skill: Terraform EKS Deployment Best Practices

## Overview
Deploying EKS with Terraform requires careful attention to state management, existing resources, and AWS-specific quirks.

## Key Learnings

### 1. S3 Backend Configuration

**NEVER use an empty backend block:**

```hcl
# ❌ BAD - causes silent failures
terraform {
  backend "s3" {
    # Backend configuration injected by pipeline
  }
}

# ✅ GOOD - explicit configuration
terraform {
  backend "s3" {
    bucket  = "my-terraform-state-bucket"
    key     = "eks/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
```

### 2. Dynamic Backend Configuration

Create backend config dynamically in scripts:

```bash
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

**Important:** Use `-reconfigure` when changing backends!

### 3. Importing Existing Resources (Idempotent Deployments)

Before `terraform apply`, import existing resources to avoid conflicts:

```bash
# Function to safely import
import_if_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local import_id="$3"
    local check_cmd="$4"
    
    # Check if already in state
    if terraform state show "${resource_type}.${resource_name}" &>/dev/null; then
        echo "  [SKIP] Already in state"
        return 0
    fi
    
    # Check if exists in AWS
    if eval "${check_cmd}" &>/dev/null; then
        echo "  [IMPORT] ${resource_type}.${resource_name}"
        terraform import -input=false "${resource_type}.${resource_name}" "${import_id}" || true
    fi
}

# Import IAM roles (they're global!)
import_if_exists "aws_iam_role" "eks_cluster" "my-cluster-eks-role" \
    "aws iam get-role --role-name my-cluster-eks-role"

# Import EKS cluster
import_if_exists "aws_eks_cluster" "main" "my-cluster" \
    "aws eks describe-cluster --name my-cluster"

# Import ECR repository
import_if_exists "aws_ecr_repository" "main" "my-repo" \
    "aws ecr describe-repositories --repository-names my-repo"

# Import VPC by ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-vpc" \
    --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" != "None" ]; then
    import_if_exists "aws_vpc" "main" "${VPC_ID}" "echo exists"
fi
```

### 4. IAM Roles Are Global

IAM roles exist globally across all regions. If you create `my-cluster-eks-role` in us-east-1, you cannot create it again in us-west-2:

```
Error: EntityAlreadyExists: Role with name my-cluster-eks-role already exists
```

**Solutions:**
1. Import existing roles into Terraform state
2. Use unique naming with region prefix
3. Clean up old roles before recreating

### 5. EKS AMI Version Compatibility

EKS node groups require AMIs that match the Kubernetes version:

```hcl
# ❌ BAD - version 1.28 may not have AMIs in all regions
variable "kubernetes_version" {
  default = "1.28"
}

# ✅ GOOD - use a well-supported version
variable "kubernetes_version" {
  default = "1.29"
}
```

Error: `InvalidParameterException: Requested AMI for this version 1.28 is not supported`

### 6. VPC Limits Per Region

AWS has VPC limits (default 5 per region):

```
Error: VpcLimitExceeded: The maximum number of VPCs has been reached
```

**Solutions:**
1. Switch to a different region
2. Request a limit increase
3. Clean up unused VPCs

### 7. Complete EKS Terraform Structure

```hcl
# providers.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# variables.tf
variable "cluster_name" {
  default = "my-eks-cluster"
}

variable "aws_region" {
  default = "us-west-2"
}

variable "kubernetes_version" {
  default = "1.29"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

# main.tf - VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}
```

## Timing Expectations

| Resource | Creation Time |
|----------|---------------|
| VPC + Subnets | ~1 minute |
| NAT Gateway | ~2 minutes |
| EKS Cluster | ~10-15 minutes |
| Node Group | ~5-7 minutes |
| **Total** | ~20-25 minutes |

## Best Practices

1. **Always use S3 backend** with versioning enabled
2. **Import existing resources** before apply for idempotency
3. **Use `-reconfigure`** when changing backends
4. **Check VPC limits** before deploying to new regions
5. **Use supported Kubernetes versions** (check AWS docs)
6. **Tag all resources** with consistent naming
7. **Output important values** (endpoint, OIDC URL, role ARNs)
