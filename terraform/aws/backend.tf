# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# 
# For initial deployment, we use local backend.
# After S3 bucket is created, switch to S3 backend for team collaboration.
#
# To migrate to S3 backend:
# 1. Uncomment the S3 backend block below
# 2. Comment out the local backend block
# 3. Run: terraform init -migrate-state
# =============================================================================

# Local backend (for initial deployment)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# S3 backend (uncomment after initial deployment)
# terraform {
#   backend "s3" {
#     bucket         = "opsera-mcp-terraform-state"
#     key            = "eks/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }
