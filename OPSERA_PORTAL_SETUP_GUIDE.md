# @opsera | Portal Configuration Guide

```
    .  ,
    |\/|
    bd "  O P S E R A
         ─────────────────
         Pipeline Setup Guide
```

---

## 📋 Prerequisites

Before configuring the pipelines, ensure you have:

- [ ] Access to Opsera Portal: https://portal.opsera.io
- [ ] `speri-aws` tool registered (ID: `694db37e487f729fe2a56cf1`)
- [ ] Git repository connected to Opsera
- [ ] AWS credentials configured in speri-aws tool

---

## 🏗️ Pipeline 1: Infrastructure Pipeline (speri-infra-r53-elb)

**Portal Link**: https://portal.opsera.io/workflow/details/6950029403c397c6c6bf697f/summary

### Step 1: Open Pipeline Editor

1. Navigate to **Pipelines** → **My Pipelines**
2. Find `speri-infra-r53-elb` or use the direct link above
3. Click **Edit Pipeline** (pencil icon)

### Step 2: Configure Terraform Step

1. Click on the **"Terraform Init - R53 & ELB"** step
2. In the step configuration panel, set:

| Field | Value |
|-------|-------|
| **Tool** | Terraform |
| **Cloud Provider** | AWS |
| **AWS Tool** | Select `speri-aws` from dropdown |
| **Backend State** | S3 (Remote State) |
| **State Bucket** | Your S3 bucket for tfstate |
| **State Key** | `speri-infra/terraform.tfstate` |

### Step 3: Configure Source Repository

1. In the same step, scroll to **Source Configuration**:

| Field | Value |
|-------|-------|
| **Repository** | Select your Git repo |
| **Branch** | `main` |
| **Terraform Path** | `terraform/aws` |

### Step 4: Configure Terraform Variables

1. Scroll to **Terraform Variables**:

```hcl
# These will be passed to terraform apply
aws_region         = "us-east-1"
environment        = "production"
project_name       = "speri-app"
vpc_id             = "vpc-0a0799fb5a48793d6"
public_subnet_ids  = ["subnet-00fc02fe051c461ee", "subnet-008a9a9c5ecccd0a1"]
private_subnet_ids = ["subnet-02aaca51e4762631d", "subnet-07277c89ab3a473cc"]
```

### Step 5: Configure Output Parameters

1. Scroll to **Output Parameters** section
2. Add these parameter mappings:

| Terraform Output | Opsera Parameter Name |
|-----------------|----------------------|
| `route53_zone_id` | `opsera-r53-zone-id` |
| `route53_fqdn` | `opsera-r53-fqdn` |
| `elb_dns_name` | `opsera-elb-dns` |
| `elb_arn` | `opsera-elb-arn` |

### Step 6: Save & Activate

1. Click **Save Step**
2. Toggle pipeline to **Active**
3. Click **Save Pipeline**

---

## 🚀 Pipeline 2: Application Pipeline (speri-app-pipeline)

**Portal Link**: https://portal.opsera.io/workflow/details/695002a403c397c6c6bf6996/summary

### Step 1: Open Pipeline Editor

1. Navigate to **Pipelines** → **My Pipelines**
2. Find `speri-app-pipeline` or use the direct link above
3. Click **Edit Pipeline** (pencil icon)

### Step 2: Configure Docker Build Step

1. Click on the **"Docker Build"** step
2. Configure:

| Field | Value |
|-------|-------|
| **Tool** | Jenkins |
| **Job Type** | Docker Build |
| **AWS Tool** | Select `speri-aws` |

**Source Configuration:**

| Field | Value |
|-------|-------|
| **Repository** | Your application repo |
| **Branch** | `main` |
| **Dockerfile Path** | `.` (root) or `Dockerfile` |

**Docker Configuration:**

| Field | Value |
|-------|-------|
| **Docker Registry** | ECR (via speri-aws) |
| **Image Name** | `speri-app` |
| **Tag Strategy** | `timestamp` or `git-sha` |

### Step 3: Configure Security Scan Step (Optional)

1. Click on **"Security Scan - Grype"** step
2. Configure:

| Field | Value |
|-------|-------|
| **Tool** | Grype |
| **Threshold Severity** | HIGH |
| **Fail on Threshold** | Yes |
| **Source Step** | Docker Build (previous step) |

### Step 4: Configure ECR Push Step

1. Click on **"Push to ECR"** step
2. Configure:

| Field | Value |
|-------|-------|
| **Tool** | AWS ECR |
| **AWS Tool** | Select `speri-aws` |
| **ECR Repository** | `speri-app` |
| **Region** | `us-east-1` |

### Step 5: Configure ECS Deploy Step

1. Click on **"Deploy to ECS"** step
2. Configure:

| Field | Value |
|-------|-------|
| **Tool** | AWS ECS |
| **AWS Tool** | Select `speri-aws` |
| **Cluster Name** | `speri-app-cluster` |
| **Service Name** | `speri-app-service` |
| **Task Definition** | Auto-update from ECR |

**Use Infrastructure Outputs** (from Pipeline 1):

| Field | Opsera Parameter |
|-------|-----------------|
| **Target Group ARN** | `${opsera-elb-arn}` |
| **Subnets** | Use private subnet IDs |

### Step 6: Save & Activate

1. Click **Save Step** for each step
2. Toggle pipeline to **Active**
3. Click **Save Pipeline**

---

## 🔗 Configure Webhook Triggers (Auto-run on Code Push)

### For GitHub Repository:

1. Go to your GitHub repo → **Settings** → **Webhooks**
2. Click **Add webhook**
3. Configure:

| Field | Value |
|-------|-------|
| **Payload URL** | `https://api.opsera.io/webhooks/github/<pipeline-id>` |
| **Content type** | `application/json` |
| **Secret** | Get from Opsera Pipeline Settings |
| **Events** | Select "Just the push event" |

### In Opsera Portal:

1. Open each pipeline
2. Go to **Settings** → **Triggers**
3. Enable **Webhook Trigger**
4. Copy the webhook URL and secret
5. Configure in your Git provider

---

## 🔄 Pipeline Execution Order

For a complete deployment, run pipelines in this order:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  1️⃣  speri-infra-r53-elb (Infrastructure)                   │
│      │                                                      │
│      ├─→ Creates VPC resources (if needed)                  │
│      ├─→ Creates Route 53 Hosted Zone                       │
│      ├─→ Creates ALB + Target Groups                        │
│      └─→ Outputs: R53 Zone ID, ELB ARN, DNS Name            │
│                                                             │
│                         ⬇️                                   │
│                                                             │
│  2️⃣  speri-app-pipeline (Application)                       │
│      │                                                      │
│      ├─→ Builds Docker image                                │
│      ├─→ Runs security scan                                 │
│      ├─→ Pushes to ECR                                      │
│      └─→ Deploys to ECS (uses infra outputs)                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Verification Checklist

After configuration, verify:

### Infrastructure Pipeline:
- [ ] Terraform step shows green checkmark
- [ ] AWS credentials validated
- [ ] S3 backend accessible
- [ ] Git repository connected

### Application Pipeline:
- [ ] All steps show green checkmarks
- [ ] Docker build configuration valid
- [ ] ECR repository exists or will be created
- [ ] ECS cluster/service configured

### Webhooks:
- [ ] Webhook URL configured in Git provider
- [ ] Test push triggers pipeline
- [ ] Notifications configured (Slack/Email)

---

## 🚀 Running Pipelines

### From Portal:
1. Open pipeline
2. Click **Run Pipeline** (play button)
3. Monitor progress in **Activity** tab

### From CLI/API (after configuration):
```bash
# After portal configuration is complete, you can run via API:
curl -X POST "https://api.opsera.io/v2/actions" \
  -H "Authorization: Bearer $OPSERA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "run",
    "type": "pipeline",
    "version": 1,
    "target": ["6950029403c397c6c6bf697f"]
  }'
```

### From Cursor (after configuration):
Once configured in the portal, return here and I can trigger the pipelines via the Opsera AI Agent.

---

## 📞 Support

- **Opsera Documentation**: https://docs.opsera.io
- **Pipeline Issues**: Check Activity logs in portal
- **Tool Configuration**: Settings → Tool Registry

---

*Generated by @opsera AI Agent*


