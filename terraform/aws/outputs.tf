# =============================================================================
# Outputs for EKS Multi-Tenant Platform
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# -----------------------------------------------------------------------------
# EKS Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "The certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OIDC identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# -----------------------------------------------------------------------------
# ECR Outputs
# -----------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

# -----------------------------------------------------------------------------
# IAM Role Outputs
# -----------------------------------------------------------------------------

output "argocd_role_arn" {
  description = "The ARN of the IAM role for ArgoCD"
  value       = aws_iam_role.argocd.arn
}

output "app_workload_role_arn" {
  description = "The ARN of the IAM role for application workloads"
  value       = aws_iam_role.app_workload.arn
}

# -----------------------------------------------------------------------------
# Kubectl Configuration
# -----------------------------------------------------------------------------

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

# -----------------------------------------------------------------------------
# Next Steps
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Next steps after cluster creation"
  value = <<-EOT
    
    =====================================================
    EKS CLUSTER CREATED SUCCESSFULLY!
    =====================================================
    
    Cluster Name: ${aws_eks_cluster.main.name}
    Region: ${var.aws_region}
    
    NEXT STEPS:
    
    1. Configure kubectl:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}
    
    2. Verify cluster access:
       kubectl get nodes
       kubectl get namespaces
    
    3. Install ArgoCD:
       kubectl create namespace argocd
       kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    4. Annotate ArgoCD service account for IRSA:
       kubectl annotate serviceaccount argocd-server -n argocd \
         eks.amazonaws.com/role-arn=${aws_iam_role.argocd.arn}
    
    5. Access ArgoCD UI:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
       # Get initial password:
       kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    
    6. Create tenant namespaces:
       kubectl create namespace tenant-a-dev
       kubectl create namespace tenant-a-stg
       kubectl create namespace tenant-b-dev
       kubectl create namespace tenant-b-stg
    
    =====================================================
  EOT
}
