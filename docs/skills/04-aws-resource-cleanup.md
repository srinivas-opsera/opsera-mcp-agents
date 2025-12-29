# Skill: AWS Resource Cleanup and Management

## Overview
Managing and cleaning up AWS resources, especially orphaned resources from failed Terraform runs.

## Key Learnings

### 1. Resource Deletion Order

AWS resources have dependencies. Delete in this order:

```
1. NAT Gateways (take 1-2 min to delete)
2. Internet Gateways (must detach first)
3. Subnets
4. Route Tables (non-main only)
5. Security Groups (non-default only)
6. VPC
7. Elastic IPs (if unassociated)
```

### 2. Find Orphaned Resources

```bash
# Find VPCs with a specific tag pattern
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=*my-prefix*" \
  --query 'Vpcs[*].{VpcId:VpcId,Name:Tags[?Key==`Name`].Value|[0],CIDR:CidrBlock}' \
  --output table

# Find NAT Gateways and their VPCs
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].{NatId:NatGatewayId,VpcId:VpcId,SubnetId:SubnetId}' \
  --output table

# Find Elastic IPs (unassociated ones cost money!)
aws ec2 describe-addresses \
  --query 'Addresses[*].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId}' \
  --output table
```

### 3. Delete NAT Gateways First

NAT Gateways take time to delete and block subnet deletion:

```bash
# Delete NAT Gateways in a specific VPC
VPC_ID="vpc-12345678"
for nat in $(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'NatGateways[*].NatGatewayId' --output text); do
    echo "Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat
done

# Wait for deletion (important!)
echo "Waiting for NAT Gateway deletion..."
sleep 120  # NAT Gateways take 1-2 minutes
```

### 4. Detach and Delete Internet Gateways

```bash
# Internet Gateways must be detached before deletion
VPC_ID="vpc-12345678"
for igw in $(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[*].InternetGatewayId' --output text); do
    echo "Detaching IGW: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID
    echo "Deleting IGW: $igw"
    aws ec2 delete-internet-gateway --internet-gateway-id $igw
done
```

### 5. Delete Subnets

```bash
VPC_ID="vpc-12345678"
for subnet in $(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' --output text); do
    echo "Deleting subnet: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet
done
```

### 6. Delete Route Tables

Only delete non-main route tables (main is auto-deleted with VPC):

```bash
VPC_ID="vpc-12345678"
for rt in $(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
    echo "Deleting route table: $rt"
    aws ec2 delete-route-table --route-table-id $rt
done
```

### 7. Delete Security Groups

Only delete non-default security groups:

```bash
VPC_ID="vpc-12345678"
for sg in $(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    echo "Deleting security group: $sg"
    aws ec2 delete-security-group --group-id $sg
done
```

### 8. Delete VPC

```bash
VPC_ID="vpc-12345678"
echo "Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id $VPC_ID
```

### 9. Release Unassociated Elastic IPs

Unassociated EIPs cost ~$3.60/month each:

```bash
# Find and release unassociated EIPs
for eip in $(aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==`null`].AllocationId' --output text); do
    echo "Releasing EIP: $eip"
    aws ec2 release-address --allocation-id $eip
done
```

### 10. Complete Cleanup Script

```bash
#!/bin/bash
# cleanup-vpc.sh - Clean up a VPC and all its resources

VPC_ID="${1:?Usage: cleanup-vpc.sh <vpc-id>}"
REGION="${AWS_REGION:-us-west-2}"

echo "Cleaning up VPC: $VPC_ID in $REGION"

# Step 1: Delete NAT Gateways
echo ">>> Deleting NAT Gateways..."
for nat in $(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query 'NatGateways[*].NatGatewayId' --output text --region $REGION 2>/dev/null); do
    [ -n "$nat" ] && aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION
done
echo "Waiting for NAT Gateway deletion..."
sleep 120

# Step 2: Detach and delete Internet Gateways
echo ">>> Deleting Internet Gateways..."
for igw in $(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[*].InternetGatewayId' --output text --region $REGION 2>/dev/null); do
    [ -n "$igw" ] && aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION
    [ -n "$igw" ] && aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION
done

# Step 3: Delete Subnets
echo ">>> Deleting Subnets..."
for subnet in $(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' --output text --region $REGION 2>/dev/null); do
    [ -n "$subnet" ] && aws ec2 delete-subnet --subnet-id $subnet --region $REGION
done

# Step 4: Delete Route Tables
echo ">>> Deleting Route Tables..."
for rt in $(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text --region $REGION 2>/dev/null); do
    [ -n "$rt" ] && aws ec2 delete-route-table --route-table-id $rt --region $REGION
done

# Step 5: Delete Security Groups
echo ">>> Deleting Security Groups..."
for sg in $(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $REGION 2>/dev/null); do
    [ -n "$sg" ] && aws ec2 delete-security-group --group-id $sg --region $REGION
done

# Step 6: Delete VPC
echo ">>> Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION

echo "Done!"
```

## Cost Implications

| Resource | Cost When Idle |
|----------|---------------|
| NAT Gateway | ~$32/month + data |
| Elastic IP (unattached) | ~$3.60/month |
| VPC | Free |
| Subnets | Free |
| Internet Gateway | Free |

**3 orphaned NAT Gateways + 3 EIPs = ~$100/month wasted!**

## Best Practices

1. **Always use Terraform destroy** instead of manual deletion
2. **Use S3 backend** to maintain state across runs
3. **Tag all resources** with project/environment tags
4. **Regular audits** for orphaned resources
5. **Set up billing alerts** to catch unexpected costs
6. **Use AWS Config** to track resource changes

