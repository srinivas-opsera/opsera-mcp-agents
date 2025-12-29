# =============================================================================
# IAM Role for Opsera Pipeline Jobs (IRSA - IAM Roles for Service Accounts)
# =============================================================================
# This creates an IAM role that can be assumed by Kubernetes pods running
# in the Opsera EKS cluster, enabling secure credential-free AWS access.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get current AWS account info
data "aws_caller_identity" "current" {}

# Get the EKS cluster OIDC provider (you need to know your cluster name)
data "aws_eks_cluster" "opsera" {
  count = var.eks_cluster_name != "" ? 1 : 0
  name  = var.eks_cluster_name
}

# -----------------------------------------------------------------------------
# IAM Policy for Terraform Operations
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "terraform_policy" {
  name        = "${var.project_name}-terraform-policy"
  description = "IAM policy for Terraform operations from Opsera pipelines"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2FullAccess"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "VPCFullAccess"
        Effect = "Allow"
        Action = [
          "vpc:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSFullAccess"
        Effect = "Allow"
        Action = [
          "ecs:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRFullAccess"
        Effect = "Allow"
        Action = [
          "ecr:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBFullAccess"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:GetRole",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:ListPolicies",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::${var.terraform_state_bucket}",
          "arn:aws:s3:::${var.terraform_state_bucket}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "STSAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "sts:AssumeRole"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IAM Role for IRSA (Web Identity)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "opsera_terraform_role" {
  name = "${var.project_name}-terraform-role"

  # Trust policy for IRSA
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${var.eks_oidc_issuer}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
          }
          StringEquals = {
            "${var.eks_oidc_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "terraform_policy_attachment" {
  role       = aws_iam_role.opsera_terraform_role.name
  policy_arn = aws_iam_policy.terraform_policy.arn
}

# -----------------------------------------------------------------------------
# Alternative: IAM Role for EC2 Instance Profile (if not using IRSA)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ec2_terraform_role" {
  count = var.create_ec2_role ? 1 : 0
  name  = "${var.project_name}-ec2-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_terraform_policy" {
  count      = var.create_ec2_role ? 1 : 0
  role       = aws_iam_role.ec2_terraform_role[0].name
  policy_arn = aws_iam_policy.terraform_policy.arn
}

resource "aws_iam_instance_profile" "terraform_profile" {
  count = var.create_ec2_role ? 1 : 0
  name  = "${var.project_name}-terraform-instance-profile"
  role  = aws_iam_role.ec2_terraform_role[0].name
}






