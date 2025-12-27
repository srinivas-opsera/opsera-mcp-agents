# =============================================================================
# @opsera | AWS Infrastructure - Route 53 before ELB Configuration
# =============================================================================
# This Terraform configuration creates:
# 1. Route 53 Hosted Zone and DNS Records (endpoint created BEFORE ELB)
# 2. Application Load Balancer with Target Groups
# 3. Security Groups for ALB and ECS
# =============================================================================

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # S3 Backend for remote state (configured via Opsera speri-aws tool)
  backend "s3" {
    # These values are provided by Opsera pipeline
    # bucket         = "terraform-state-bucket"
    # key            = "speri-infra/terraform.tfstate"
    # region         = "us-east-1"
    # encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Opsera-Terraform"
      Pipeline    = "speri-infra-r53-elb"
    }
  }
}

# =============================================================================
# VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "speri-app"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
  default     = "speri-app.example.com"
}

variable "vpc_id" {
  description = "VPC ID for ALB"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "container_port" {
  description = "Container port for the application"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/health"
}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# =============================================================================
# ROUTE 53 - Created BEFORE ELB (DNS Endpoint First)
# =============================================================================

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Managed by Opsera - Route 53 zone created before ELB"

  tags = {
    Name        = "${var.project_name}-zone"
    CreatedBy   = "speri-infra-r53-elb-pipeline"
    OrderNote   = "Created BEFORE ELB"
  }
}

# Placeholder A record - will be updated with ALB alias after ELB creation
resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_route53_zone.main]
}

# Health check for Route 53
resource "aws_route53_health_check" "main" {
  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name = "${var.project_name}-health-check"
  }

  depends_on = [aws_route53_zone.main]
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}

# =============================================================================
# APPLICATION LOAD BALANCER (Created AFTER Route 53)
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true

  tags = {
    Name        = "${var.project_name}-alb"
    CreatedBy   = "speri-infra-r53-elb-pipeline"
    OrderNote   = "Created AFTER R53 Zone"
  }

  # Ensure R53 zone exists before creating ELB
  depends_on = [aws_route53_zone.main]
}

# Target Group
resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# HTTPS Listener (requires ACM certificate)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  depends_on = [aws_acm_certificate_validation.main]
}

# HTTP to HTTPS redirect
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# =============================================================================
# ACM CERTIFICATE
# =============================================================================

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# =============================================================================
# OUTPUTS - Captured by Opsera Pipeline
# =============================================================================

output "route53_zone_id" {
  description = "Route 53 Hosted Zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_fqdn" {
  description = "Route 53 FQDN"
  value       = aws_route53_record.app.fqdn
}

output "route53_name_servers" {
  description = "Route 53 Name Servers"
  value       = aws_route53_zone.main.name_servers
}

output "elb_dns_name" {
  description = "Application Load Balancer DNS Name"
  value       = aws_lb.main.dns_name
}

output "elb_arn" {
  description = "Application Load Balancer ARN"
  value       = aws_lb.main.arn
}

output "elb_zone_id" {
  description = "Application Load Balancer Zone ID"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.main.arn
}

output "alb_security_group_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ECS Tasks Security Group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "acm_certificate_arn" {
  description = "ACM Certificate ARN"
  value       = aws_acm_certificate.main.arn
}

