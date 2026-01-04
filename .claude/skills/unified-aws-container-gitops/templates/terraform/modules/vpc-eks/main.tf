# =============================================================================
# VPC + EKS REUSABLE MODULE
# =============================================================================
# This module creates a complete VPC and EKS cluster in a single, reusable unit.
# It's designed to be called from different environments (nonprod, prod, etc.)
#
# Usage:
#   module "vpc_eks" {
#     source       = "./modules/vpc-eks"
#     cluster_name = "my-cluster"
#     environment  = "nonprod"
#     aws_region   = "us-west-1"
#     vpc_cidr     = "10.0.0.0/16"
#   }
# =============================================================================

# -----------------------------------------------------------------------------
# VARIABLES
# -----------------------------------------------------------------------------
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (nonprod, prod, etc.)"
  type        = string
  default     = "nonprod"
}

variable "aws_region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "us-west-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 5
}

variable "enable_irsa" {
  description = "Enable IRSA (IAM Roles for Service Accounts)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# LOCAL VALUES
# -----------------------------------------------------------------------------
locals {
  # Use only first 3 AZs (some regions like us-west-1 have limited AZs)
  azs = slice(data.aws_availability_zones.available.names, 0, min(3, length(data.aws_availability_zones.available.names)))

  common_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
    Environment = var.environment
  })
}

# -----------------------------------------------------------------------------
# VPC MODULE
# -----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 4)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "prod" # Cost optimization for non-prod
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS to auto-discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = 1
    "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = 1
    "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS CLUSTER MODULE
# -----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint for kubectl access (enable private for production)
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # OIDC for IRSA
  enable_irsa = var.enable_irsa

  # Node groups
  eks_managed_node_groups = {
    general = {
      name = "${var.cluster_name}-general"

      instance_types = var.node_instance_types
      capacity_type  = var.environment == "prod" ? "ON_DEMAND" : "SPOT"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        role        = "general"
        environment = var.environment
      }

      tags = local.common_tags
    }
  }

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# ECR REPOSITORY (Optional - for apps using this cluster)
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  count = var.environment == "nonprod" ? 1 : 0

  name                 = var.cluster_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle {
    prevent_destroy = false
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# IRSA: EXTERNAL DNS
# -----------------------------------------------------------------------------
module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-dns"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  role_policy_arns = {
    external_dns = aws_iam_policy.external_dns.arn
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "external_dns" {
  name        = "${var.cluster_name}-external-dns"
  description = "External DNS policy for Route53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# IRSA: AWS LOAD BALANCER CONTROLLER
# -----------------------------------------------------------------------------
module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-aws-lb-controller"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  role_policy_arns = {
    aws_lb_controller = aws_iam_policy.aws_lb_controller.arn
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "aws_lb_controller" {
  name        = "${var.cluster_name}-aws-lb-controller"
  description = "AWS Load Balancer Controller policy"

  # This is a simplified policy - see AWS docs for full policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeInternetGateways",
          "elasticloadbalancing:*",
          "acm:DescribeCertificate",
          "acm:ListCertificates"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = module.eks.cluster_oidc_issuer_url
}

output "external_dns_role_arn" {
  description = "External DNS IRSA role ARN"
  value       = module.external_dns_irsa.iam_role_arn
}

output "aws_lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IRSA role ARN"
  value       = module.aws_lb_controller_irsa.iam_role_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL (nonprod only)"
  value       = var.environment == "nonprod" ? aws_ecr_repository.app[0].repository_url : null
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region}"
}
