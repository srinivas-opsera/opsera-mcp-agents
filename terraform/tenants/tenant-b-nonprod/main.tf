# =============================================================================
# TenantB - Non-Production Environment
# =============================================================================

terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket = "opsera-agentic-s3-v1"
    key    = "tenants/tenant-b/nonprod/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Terraform   = "true"
      Tenant      = "TenantB"
      Environment = "nonprod"
    }
  }
}

module "vpc_eks" {
  source = "../../modules/vpc-eks"

  tenant_name = "TenantB"
  environment = "nonprod"
  aws_region  = var.aws_region

  # VPC Configuration - Using 10.3.x.x range for TenantB
  vpc_cidr             = "10.3.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b"]
  public_subnet_cidrs  = ["10.3.1.0/24", "10.3.2.0/24"]
  private_subnet_cidrs = ["10.3.10.0/24", "10.3.20.0/24"]
  enable_nat_gateway   = true

  # EKS Configuration - Cost-optimized for non-prod
  kubernetes_version  = "1.29"
  node_instance_types = ["t3.medium"]
  node_capacity_type  = "SPOT"  # Use spot instances for cost savings
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 4

  additional_tags = {
    CostCenter = "tenant-b-nonprod"
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# Outputs
output "vpc_id" {
  value = module.vpc_eks.vpc_id
}

output "cluster_name" {
  value = module.vpc_eks.cluster_name
}

output "cluster_endpoint" {
  value = module.vpc_eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = module.vpc_eks.kubeconfig_command
}

