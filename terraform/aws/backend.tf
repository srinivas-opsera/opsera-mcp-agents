# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Using S3 backend for state persistence across pipeline runs.
# The bucket was created during initial deployment.
# =============================================================================

terraform {
  backend "s3" {
    bucket  = "opsera-agentic-s3-v1"
    key     = "opsera-mcp-agents/eks-terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
