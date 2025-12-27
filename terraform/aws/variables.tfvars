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

# VPC Configuration - dev VPC (fetched from AWS)
vpc_id = "vpc-0a0799fb5a48793d6"

public_subnet_ids = [
  "subnet-00fc02fe051c461ee",  # pub-1-dev (us-east-1a)
  "subnet-008a9a9c5ecccd0a1"   # pub-2-dev (us-east-1b)
]

private_subnet_ids = [
  "subnet-02aaca51e4762631d",  # priv-1-dev (us-east-1a)
  "subnet-07277c89ab3a473cc"   # priv-2-dev (us-east-1b)
]

# Application settings
container_port    = 3000
health_check_path = "/health"

