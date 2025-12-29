# Skills & Learnings

This directory contains documented skills and best practices learned from deploying multi-tenant GitOps infrastructure on AWS EKS using Opsera pipelines.

## Skills Index

| Skill | Description | Key Learnings |
|-------|-------------|---------------|
| [Opsera run_script Limitations](./opsera-run-script-limitations.md) | Understanding the limitations of Opsera's run_script tool | AWS creds not auto-injected, no git clone, manual tool installation required |
| [Opsera Pipeline Creation](./opsera-pipeline-creation.md) | API best practices for creating Opsera pipelines | Valid ObjectId format, correct field names, native Terraform config |
| [Terraform EKS Deployment](./terraform-eks-deployment.md) | Best practices for deploying EKS with Terraform | S3 backend, importing existing resources, common errors |
| [ArgoCD Multi-Tenant GitOps](./argocd-multi-tenant-gitops.md) | Setting up multi-tenant GitOps architecture | App-of-Apps pattern, ApplicationSets, tenant isolation |
| [Idempotent Deployment Scripts](./idempotent-deployment-scripts.md) | Writing scripts that can be run multiple times safely | Check-before-create patterns, non-interactive flags |
| [AWS Resource Cleanup](./aws-resource-cleanup.md) | Safe patterns for cleaning up AWS resources | Dependency order, VPC cleanup, cost savings |

## Quick Reference

### Opsera run_script Key Points
- ❌ `awsToolConfigId` does NOT inject AWS credentials
- ❌ Template syntax (`{{aws.accessKeyId}}`) does NOT work
- ❌ `environmentConfiguration.image` is ignored
- ✅ Use `type: "manual_entry"` (not `"github"`)
- ✅ Use `script` field (not `commands`)
- ✅ Manually install all tools in script

### Terraform Import Pattern
```bash
terraform import aws_iam_role.eks_cluster my-cluster-eks-cluster-role
terraform import aws_ecr_repository.main my-repo-name
terraform import aws_eks_cluster.main my-cluster-name
```

### Idempotent Kubernetes Commands
```bash
kubectl create namespace X --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifest.yaml  # Always use apply, not create
```

### Non-Interactive Flags
| Tool | Flag |
|------|------|
| unzip | `-o` |
| apt-get | `-y -qq` |
| terraform | `-input=false -auto-approve` |
| npm/npx | `--yes` |

### VPC Cleanup Order
1. NAT Gateways → 2. Elastic IPs → 3. Internet Gateways → 4. Subnets → 5. Route Tables → 6. Security Groups → 7. VPC

## Session Summary

### What We Built
- EKS Cluster (`opsera-mcp-dev`) in us-west-2
- Multi-tenant ArgoCD GitOps (Tenants A, B, C)
- 9 namespaces (3 tenants × 3 environments)
- IRSA roles for secure AWS access
- ECR repository for container images
- S3 backend for Terraform state

### Architecture
```
EKS Cluster
├── argocd namespace
│   ├── ArgoCD Server
│   └── Root App-of-Apps
└── Tenant Namespaces
    ├── tenant-a-dev, tenant-a-stg, tenant-a-prod
    ├── tenant-b-dev, tenant-b-stg, tenant-b-prod
    └── tenant-c-dev, tenant-c-stg, tenant-c-prod
```

### Scripts
| Script | Purpose |
|--------|---------|
| `scripts/full-deploy.sh` | Complete EKS + ArgoCD deployment |
| `scripts/eks-deploy-simple.sh` | Terraform EKS only |
| `scripts/bootstrap-argocd.sh` | ArgoCD installation only |

### Opsera Pipelines
| Pipeline | Status |
|----------|--------|
| `eks-deploy-simple-v1` | ✅ Works (needs AWS creds) |
| `argocd-bootstrap-v1` | ❌ Fails (run_script cred limitation) |

## Lessons Learned

1. **Opsera `run_script` is a bare executor** - no credential injection, no git clone, no custom images
2. **IAM roles are global** - importing required when recreating clusters
3. **S3 backend is essential** - local backend loses state between runs
4. **Idempotency is critical** - always check before creating
5. **Cleanup order matters** - NAT Gateways before VPCs
6. **Non-interactive flags required** - pipelines can't prompt for input

