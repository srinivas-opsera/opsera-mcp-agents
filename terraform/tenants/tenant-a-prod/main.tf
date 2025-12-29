# =============================================================================
# TenantA - Production Environment
# =============================================================================

terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket = "opsera-agentic-s3-v1"
    key    = "tenants/tenant-a/prod/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Terraform   = "true"
      Tenant      = "TenantA"
      Environment = "prod"
    }
  }
}

module "vpc_eks" {
  source = "../../modules/vpc-eks"

  tenant_name = "TenantA"
  environment = "prod"
  aws_region  = var.aws_region

  # VPC Configuration - Using 10.2.x.x range for TenantA Prod
  vpc_cidr             = "10.2.0.0/16"
  availability_zones   = ["us-west-2a", "us-west-2b"]
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.20.0/24"]
  enable_nat_gateway   = true

  # EKS Configuration - Production-grade
  kubernetes_version  = "1.29"
  node_instance_types = ["t3.large"]     # Larger instances for prod
  node_capacity_type  = "ON_DEMAND"      # Reliable on-demand for prod
  node_desired_size   = 3
  node_min_size       = 2
  node_max_size       = 6

  additional_tags = {
    CostCenter  = "tenant-a-prod"
    Criticality = "high"
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

