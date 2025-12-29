# =============================================================================
# Variables for IAM Role Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "opsera-mcp-agents"
}

# -----------------------------------------------------------------------------
# EKS OIDC Configuration (Required for IRSA)
# -----------------------------------------------------------------------------

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (leave empty if not using data source)"
  type        = string
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (e.g., arn:aws:iam::123456789:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE)"
  type        = string
}

variable "eks_oidc_issuer" {
  description = "OIDC issuer URL without https:// (e.g., oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE)"
  type        = string
}

# -----------------------------------------------------------------------------
# Kubernetes Configuration
# -----------------------------------------------------------------------------

variable "kubernetes_namespace" {
  description = "Kubernetes namespace where Opsera jobs run"
  type        = string
  default     = "opsera"  # Common Opsera namespace - verify with your setup
}

variable "kubernetes_service_account" {
  description = "Kubernetes service account name used by Opsera jobs"
  type        = string
  default     = "*"  # Wildcard to allow any SA in the namespace
}

# -----------------------------------------------------------------------------
# S3 Configuration for Terraform State
# -----------------------------------------------------------------------------

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "Opsera-agentic-s3-v1"
}

# -----------------------------------------------------------------------------
# Optional: EC2 Instance Profile
# -----------------------------------------------------------------------------

variable "create_ec2_role" {
  description = "Whether to create an EC2 instance profile (for non-IRSA setups)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "opsera-mcp-agents"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "pipeline-iam"
  }
}


