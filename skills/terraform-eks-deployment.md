# Terraform EKS Deployment - Best Practices

## Overview
Deploying EKS clusters with Terraform requires careful handling of state, existing resources, and idempotency. This skill documents lessons learned from production deployments.

## Multi-Tenant Architecture

### CIDR Allocation Strategy
When deploying multiple VPCs for tenant isolation:
```
ArgoCD-GitOps-VPC:  10.0.0.0/16  (Management)
TenantA-nonprod:     10.1.0.0/16
TenantA-prod:        10.2.0.0/16
TenantB-nonprod:     10.3.0.0/16
TenantB-prod:        10.4.0.0/16
```

### Subnet Layout per VPC
```
Public Subnets:   10.x.1.0/24, 10.x.2.0/24  (AZ-a, AZ-b)
Private Subnets:  10.x.10.0/24, 10.x.20.0/24 (AZ-a, AZ-b)
```

### Non-Prod vs Prod Configuration
| Setting | Non-Prod | Prod |
|---------|----------|------|
| Node Capacity | SPOT | ON_DEMAND |
| Instance Type | t3.medium | t3.large |
| Node Count | 2 (min 1, max 4) | 3 (min 2, max 6) |
| Logging | api, audit | all 5 types |

## S3 Backend for State Persistence

### Why S3 Backend?
- Local backend loses state between pipeline runs
- S3 provides persistent, shared state
- Enables team collaboration and state locking

### Multi-Tenant State Keys
```hcl
# Each tenant/environment gets separate state
terraform {
  backend "s3" {
    bucket  = "opsera-agentic-s3-v1"
    key     = "tenants/tenant-a/nonprod/terraform.tfstate"  # Unique per tenant
    region  = "us-east-1"
    encrypt = true
  }
}
```

### Dynamic Backend in Scripts
```bash
S3_BUCKET="your-bucket"
S3_KEY="path/to/state.tfstate"

cat > backend_override.tf << EOF
terraform {
  backend "s3" {
    bucket  = "${S3_BUCKET}"
    key     = "${S3_KEY}"
    region  = "us-east-1"
    encrypt = true
  }
}
EOF

terraform init -input=false -reconfigure
```

## Importing Existing Resources

### Why Import?
- IAM roles are **global** - they exist across all regions
- ECR repositories persist even after cluster deletion
- VPCs may have been created manually or by other tools
- **Interrupted deployments leave resources without state**

### Safe Import Function
```bash
import_if_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local import_id="$3"
    local check_cmd="$4"
    
    # Check if already in state
    if terraform state show "${resource_type}.${resource_name}" &>/dev/null; then
        echo "[SKIP] ${resource_type}.${resource_name} already in state"
        return 0
    fi
    
    # Check if exists in AWS
    if eval "${check_cmd}" &>/dev/null; then
        echo "[IMPORT] ${resource_type}.${resource_name} <- ${import_id}"
        terraform import -input=false "${resource_type}.${resource_name}" "${import_id}" || true
    else
        echo "[NEW] ${resource_type}.${resource_name} will be created"
    fi
}

# Usage examples
import_if_exists "aws_iam_role" "eks_cluster" "cluster-name-eks-cluster-role" \
    "aws iam get-role --role-name cluster-name-eks-cluster-role"

import_if_exists "aws_ecr_repository" "main" "repo-name" \
    "aws ecr describe-repositories --repository-names repo-name"

import_if_exists "aws_eks_cluster" "main" "cluster-name" \
    "aws eks describe-cluster --name cluster-name"
```

### Recovering from Interrupted Deployments
When a Terraform apply is interrupted, you may need to import resources that were created but not recorded in state:

```bash
# 1. Import EKS cluster
terraform import 'module.vpc_eks.aws_eks_cluster.main' TenantB-nonprod

# 2. Import NAT gateway (find correct ID first)
NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'NatGateways[0].NatGatewayId' --output text --region us-west-2)
terraform import 'module.vpc_eks.aws_nat_gateway.main[0]' $NAT_ID

# 3. Import route table
terraform import 'module.vpc_eks.aws_route_table.private' rtb-xxxx

# 4. Import route table associations
terraform import 'module.vpc_eks.aws_route_table_association.private[0]' "subnet-xxxx/rtb-xxxx"

# 5. Import node group
terraform import 'module.vpc_eks.aws_eks_node_group.main' ClusterName:NodeGroupName

# 6. Untaint resources marked for replacement
terraform untaint 'module.vpc_eks.aws_nat_gateway.main[0]'

# 7. Verify no changes needed
terraform plan
```

## Common EKS Deployment Errors

### 1. VpcLimitExceeded
**Error**: `The maximum number of VPCs has been reached`
**Solution**: Switch to a different region or delete unused VPCs
```bash
# Check VPC count
aws ec2 describe-vpcs --query 'length(Vpcs)'
```

### 2. EntityAlreadyExists (IAM Roles)
**Error**: `Role with name X already exists`
**Solution**: Import the role or delete it first
```bash
# Import existing role
terraform import aws_iam_role.eks_cluster cluster-name-eks-cluster-role

# Or delete (if orphaned)
aws iam delete-role --role-name old-role-name
```

### 3. InvalidParameterException (AMI)
**Error**: `Requested AMI for this version X is not supported`
**Solution**: Update `kubernetes_version` in variables
```hcl
variable "kubernetes_version" {
  default = "1.29"  # Use a supported version
}
```

### 4. RepositoryAlreadyExistsException (ECR)
**Error**: `The repository with name X already exists`
**Solution**: Import the ECR repository
```bash
terraform import aws_ecr_repository.main repo-name
```

### 5. Resource.AlreadyAssociated (EIP/NAT)
**Error**: `Elastic IP address [eipalloc-xxx] is already associated`
**Solution**: Import the correct NAT gateway, don't create a new one
```bash
# Find the working NAT gateway
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'NatGateways[0].NatGatewayId' --output text

# Remove wrong resource from state and import correct one
terraform state rm 'module.vpc_eks.aws_nat_gateway.main[0]'
terraform import 'module.vpc_eks.aws_nat_gateway.main[0]' nat-correct-id
```

### 6. Node Group CREATING but Nodes Not Joining
**Symptom**: Node group stuck in CREATING, EC2 instances running but not registering
**Cause**: Private subnets have no route to NAT gateway
**Solution**: 
```bash
# Check if private route table has NAT route
aws ec2 describe-route-tables --route-table-ids rtb-xxx --query 'RouteTables[0].Routes'

# Add NAT route if missing
aws ec2 create-route --route-table-id rtb-xxx --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-xxx
```

## EKS Cluster Wait Pattern
```bash
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

case "$CLUSTER_STATUS" in
    "ACTIVE")
        echo "Cluster is ready"
        ;;
    "CREATING"|"UPDATING")
        echo "Waiting for cluster..."
        aws eks wait cluster-active --name "${CLUSTER_NAME}"
        ;;
    "NOT_FOUND")
        echo "Cluster will be created by Terraform"
        ;;
esac
```

## Recommended Module Structure for Multi-Tenant
```
terraform/
├── modules/
│   └── vpc-eks/
│       ├── main.tf          # VPC, EKS, Node Groups
│       ├── variables.tf     # tenant_name, environment, vpc_cidr, etc.
│       ├── outputs.tf       # cluster_endpoint, vpc_id, kubeconfig_command
│       └── providers.tf     # AWS and TLS providers
├── tenants/
│   ├── tenant-a-nonprod/
│   │   └── main.tf          # Module call with tenant-specific config
│   ├── tenant-a-prod/
│   │   └── main.tf
│   ├── tenant-b-nonprod/
│   │   └── main.tf
│   └── tenant-b-prod/
│       └── main.tf
```

## Key Outputs to Export
```hcl
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  value     = aws_eks_cluster.main.certificate_authority[0].data
  sensitive = true
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.aws_region}"
}

output "vpc_id" {
  value = aws_vpc.main.id
}
```

## Idempotency Checklist

Before considering a deployment "complete", verify:

1. **State matches reality**: `terraform plan` shows "No changes"
2. **All resources imported**: No orphaned AWS resources outside of state
3. **No tainted resources**: `terraform state list` shows no tainted resources
4. **Route tables configured**: Private subnets have NAT gateway route
5. **Node group active**: Nodes are registered and Ready
```bash
# Verify idempotency
terraform plan  # Should show "No changes"

# Verify nodes
kubectl get nodes  # Should show Ready nodes
```
