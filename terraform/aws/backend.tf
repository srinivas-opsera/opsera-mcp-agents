# ═══════════════════════════════════════════════════════════════════════════════
# Opsera MCP Agents - Terraform Backend Configuration  
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Using local backend for testing - switch to S3 after validation
# ═══════════════════════════════════════════════════════════════════════════════

# Temporarily disabled S3 backend for debugging
# terraform {
#   backend "s3" {
#     bucket  = "Opsera-agentic-s3-v1"
#     key     = "opsera-mcp-agents/terraform.tfstate"
#     region  = "us-east-1"
#     encrypt = true
#   }
# }
