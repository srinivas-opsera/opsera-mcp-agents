# AWS Resource Cleanup - Safe Deletion Patterns

## Overview
Cleaning up AWS resources requires deleting them in the correct order due to dependencies. This skill documents the proper sequence and commands for safe cleanup.

## Dependency Order for VPC Cleanup

Resources must be deleted in this order (reverse of creation):

```
1. NAT Gateways (takes ~2 min to fully delete)
2. Elastic IPs (release after NAT deletion)
3. Internet Gateways (detach, then delete)
4. Subnets
5. Route Tables (non-main only)
6. Security Groups (non-default only)
7. Network ACLs (if custom)
8. VPC Endpoints (if any)
9. VPC
```

## Complete VPC Cleanup Script

```bash
#!/bin/bash
# Safe VPC cleanup script
set -e

VPC_ID="$1"
REGION="${2:-us-west-2}"

if [ -z "$VPC_ID" ]; then
    echo "Usage: $0 <vpc-id> [region]"
    exit 1
fi

echo "=== Cleaning up VPC: $VPC_ID in $REGION ==="

# Step 1: Delete NAT Gateways
echo ">>> Deleting NAT Gateways..."
for nat in $(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
    --query 'NatGateways[*].NatGatewayId' --output text --region $REGION); do
    echo "  Deleting: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION
done

# Wait for NAT Gateways to be deleted
echo ">>> Waiting for NAT Gateways to be deleted (60s)..."
sleep 60

# Verify NAT deletion
for nat in $(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=deleting" \
    --query 'NatGateways[*].NatGatewayId' --output text --region $REGION); do
    echo "  Waiting for: $nat"
    aws ec2 wait nat-gateway-available --nat-gateway-ids $nat --region $REGION 2>/dev/null || true
done

# Step 2: Release Elastic IPs (unassociated ones)
echo ">>> Releasing unassociated Elastic IPs..."
for eip in $(aws ec2 describe-addresses \
    --filters "Name=domain,Values=vpc" \
    --query 'Addresses[?AssociationId==`null`].AllocationId' \
    --output text --region $REGION); do
    echo "  Releasing: $eip"
    aws ec2 release-address --allocation-id $eip --region $REGION 2>/dev/null || true
done

# Step 3: Detach and Delete Internet Gateways
echo ">>> Deleting Internet Gateways..."
for igw in $(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[*].InternetGatewayId' --output text --region $REGION); do
    echo "  Detaching: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION
    echo "  Deleting: $igw"
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION
done

# Step 4: Delete Subnets
echo ">>> Deleting Subnets..."
for subnet in $(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' --output text --region $REGION); do
    echo "  Deleting: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null || \
        echo "    (may have dependencies)"
done

# Step 5: Delete Route Tables (non-main)
echo ">>> Deleting Route Tables..."
for rt in $(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
    --output text --region $REGION); do
    
    # Disassociate first
    for assoc in $(aws ec2 describe-route-tables --route-table-ids $rt \
        --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
        --output text --region $REGION); do
        aws ec2 disassociate-route-table --association-id $assoc --region $REGION 2>/dev/null || true
    done
    
    echo "  Deleting: $rt"
    aws ec2 delete-route-table --route-table-id $rt --region $REGION 2>/dev/null || true
done

# Step 6: Delete Security Groups (non-default)
echo ">>> Deleting Security Groups..."
for sg in $(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text --region $REGION); do
    echo "  Deleting: $sg"
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null || \
        echo "    (may have dependencies)"
done

# Step 7: Delete VPC Endpoints
echo ">>> Deleting VPC Endpoints..."
for endpoint in $(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'VpcEndpoints[*].VpcEndpointId' --output text --region $REGION); do
    echo "  Deleting: $endpoint"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $endpoint --region $REGION
done

# Step 8: Delete VPC
echo ">>> Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION

echo "=== VPC $VPC_ID deleted successfully ==="
```

## EKS Cluster Cleanup

```bash
# Delete node groups first
for ng in $(aws eks list-nodegroups --cluster-name $CLUSTER \
    --query 'nodegroups' --output text --region $REGION); do
    echo "Deleting node group: $ng"
    aws eks delete-nodegroup --cluster-name $CLUSTER --nodegroup-name $ng --region $REGION
    aws eks wait nodegroup-deleted --cluster-name $CLUSTER --nodegroup-name $ng --region $REGION
done

# Delete the cluster
aws eks delete-cluster --name $CLUSTER --region $REGION
aws eks wait cluster-deleted --name $CLUSTER --region $REGION
```

## IAM Role Cleanup

```bash
ROLE_NAME="my-role"

# Detach managed policies
for policy in $(aws iam list-attached-role-policies --role-name $ROLE_NAME \
    --query 'AttachedPolicies[*].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $policy
done

# Delete inline policies
for policy in $(aws iam list-role-policies --role-name $ROLE_NAME \
    --query 'PolicyNames' --output text); do
    aws iam delete-role-policy --role-name $ROLE_NAME --policy-name $policy
done

# Delete instance profiles
for profile in $(aws iam list-instance-profiles-for-role --role-name $ROLE_NAME \
    --query 'InstanceProfiles[*].InstanceProfileName' --output text); do
    aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $ROLE_NAME
done

# Delete the role
aws iam delete-role --role-name $ROLE_NAME
```

## Finding Orphaned Resources

```bash
# Find VPCs with specific tags
aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=*my-project*" \
    --query 'Vpcs[*].{VpcId:VpcId,Name:Tags[?Key==`Name`].Value|[0]}' \
    --output table --region $REGION

# Find unattached Elastic IPs (costing money!)
aws ec2 describe-addresses \
    --filters "Name=domain,Values=vpc" \
    --query 'Addresses[?AssociationId==`null`].{AllocationId:AllocationId,PublicIp:PublicIp}' \
    --output table --region $REGION

# Find unused NAT Gateways
aws ec2 describe-nat-gateways \
    --filter "Name=state,Values=available" \
    --query 'NatGateways[*].{NatId:NatGatewayId,VpcId:VpcId}' \
    --output table --region $REGION
```

## Cost Implications

| Resource | Cost When Idle |
|----------|----------------|
| NAT Gateway | ~$32/month + data |
| Elastic IP (unattached) | ~$3.60/month |
| Load Balancer | ~$16/month + data |
| EBS Volumes | ~$0.10/GB/month |

## Safety Checks Before Deletion

```bash
# Check if VPC is in use
check_vpc_usage() {
    local vpc_id=$1
    
    # Check for running instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text)
    
    if [ -n "$instances" ]; then
        echo "WARNING: VPC has running instances: $instances"
        return 1
    fi
    
    # Check for RDS instances
    # Check for EKS clusters
    # etc.
    
    return 0
}
```

## Terraform Destroy (Preferred Method)

When resources were created by Terraform, use `terraform destroy`:

```bash
cd terraform/directory
terraform init
terraform destroy -auto-approve
```

This ensures all resources are deleted in the correct order with proper dependency resolution.

