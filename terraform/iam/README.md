# IAM Role for Opsera Pipeline Jobs (IRSA)

This Terraform configuration creates an IAM role that can be assumed by Kubernetes pods running in the Opsera EKS cluster, enabling secure credential-free AWS access using **IAM Roles for Service Accounts (IRSA)**.

## Prerequisites

1. **EKS Cluster with OIDC Provider**: Your EKS cluster must have an OIDC identity provider configured
2. **AWS CLI**: For getting cluster information
3. **kubectl**: For configuring the service account
4. **Terraform**: v1.0+

## Step 1: Get EKS OIDC Information

```bash
# Get your EKS cluster's OIDC issuer URL
aws eks describe-cluster --name <your-cluster-name> --query "cluster.identity.oidc.issuer" --output text

# Example output:
# https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
```

## Step 2: Configure terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Key values to set:
- `eks_oidc_provider_arn`: Full ARN of the OIDC provider
- `eks_oidc_issuer`: OIDC issuer URL (without `https://`)
- `kubernetes_namespace`: Namespace where Opsera jobs run (usually `opsera`)
- `kubernetes_service_account`: Service account name or `*` for any

## Step 3: Deploy the IAM Role

```bash
terraform init
terraform plan
terraform apply
```

## Step 4: Configure Opsera

### Option A: Update Service Account (Recommended)

```bash
# Annotate the Opsera job service account with the IAM role ARN
kubectl annotate serviceaccount <opsera-job-sa> \
  -n opsera \
  eks.amazonaws.com/role-arn=<role-arn-from-terraform-output>
```

### Option B: Update Opsera Tool Registry

1. Go to **Operations** > **Tool Registry** > **AWS**
2. Edit your AWS tool (`speri-aws`)
3. Set **IAM Role ARN** to the output from Terraform
4. Enable **Use IAM Role** or **Cross Account IAM Role** option
5. Save

## Step 5: Test

Run pipeline `opsera-check-irsa-v34` to verify IRSA is working.

## Troubleshooting

### No OIDC Provider

```bash
# Create OIDC provider for your cluster
eksctl utils associate-iam-oidc-provider --cluster <cluster-name> --approve
```

### Check Service Account Annotation

```bash
kubectl get sa -n opsera -o yaml | grep eks.amazonaws.com/role-arn
```

### Check Pod Environment

The pod should have these environment variables:
- `AWS_ROLE_ARN`
- `AWS_WEB_IDENTITY_TOKEN_FILE`

## Permissions Granted

The IAM role includes permissions for:
- EC2 (VPC, subnets, security groups)
- ECS (clusters, services, tasks)
- ECR (repositories, images)
- ELB (load balancers)
- S3 (Terraform state bucket)
- IAM (role management for ECS tasks)
- CloudWatch Logs

## Security Notes

- The role can only be assumed by pods in the specified namespace/service account
- Credentials are automatically rotated by EKS
- No long-lived access keys are stored


