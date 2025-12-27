# =============================================================================
# @opsera | Terraform Variables for speri-infra-r53-elb Pipeline
# =============================================================================
# Update these values for your environment
# =============================================================================

aws_region   = "us-east-1"
environment  = "production"
project_name = "speri-app"

# Domain configuration
domain_name = "app.yourdomain.com"

# VPC Configuration (update with your VPC and subnet IDs)
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"

public_subnet_ids = [
  "subnet-xxxxxxxxxxxxxxxxx",
  "subnet-yyyyyyyyyyyyyyyyy"
]

private_subnet_ids = [
  "subnet-aaaaaaaaaaaaaaaa",
  "subnet-bbbbbbbbbbbbbbbb"
]

# Application settings
container_port    = 3000
health_check_path = "/health"

