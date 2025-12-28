# ═══════════════════════════════════════════════════════════════════════════════
# Opsera MCP Agents - Terraform Outputs
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# VPC Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

# ─────────────────────────────────────────────────────────────────────────────────
# ECR Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

# ─────────────────────────────────────────────────────────────────────────────────
# ECS Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "ecs_cluster_id" {
  description = "The ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "ecs_task_definition_arn" {
  description = "The ARN of the ECS task definition"
  value       = aws_ecs_task_definition.main.arn
}

# ─────────────────────────────────────────────────────────────────────────────────
# Load Balancer Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "The zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "The ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "The ARN of the target group"
  value       = aws_lb_target_group.main.arn
}

# ─────────────────────────────────────────────────────────────────────────────────
# Application URL
# ─────────────────────────────────────────────────────────────────────────────────

output "application_url" {
  description = "The URL to access the application"
  value       = "http://${aws_lb.main.dns_name}"
}

# ─────────────────────────────────────────────────────────────────────────────────
# Security Group Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "alb_security_group_id" {
  description = "The ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "The ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

# ─────────────────────────────────────────────────────────────────────────────────
# IAM Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "ecs_task_execution_role_arn" {
  description = "The ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "The ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

# ─────────────────────────────────────────────────────────────────────────────────
# CloudWatch Outputs
# ─────────────────────────────────────────────────────────────────────────────────

output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.arn
}

