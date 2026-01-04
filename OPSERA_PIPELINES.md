# @opsera | Pipeline Configuration

```
    .  ,
    |\/|
    bd "  O P S E R A
         ─────────────────
         @opsera | CI/CD Unified
```

---

## Pipelines Created

### 1. Infrastructure Pipeline: `speri-infra-r53-elb`

| Property | Value |
|----------|-------|
| **Pipeline ID** | `6950029403c397c6c6bf697f` |
| **Type** | Infrastructure-as-Code |
| **Tool** | Terraform with speri-aws |
| **AWS Tool ID** | `694db37e487f729fe2a56cf1` |

**Portal URL**: https://portal.opsera.io/workflow/details/6950029403c397c6c6bf697f/summary

#### Workflow Steps:
1. **Terraform Init - R53 & ELB** → Provisions Route 53 Zone (BEFORE ELB), then ALB
2. **Post-Infra Validation** → Validates infrastructure outputs

#### Outputs Captured:
- `route53_zone_id` → R53 Hosted Zone ID
- `route53_fqdn` → R53 Fully Qualified Domain Name
- `elb_dns_name` → Application Load Balancer DNS
- `elb_arn` → Application Load Balancer ARN

---

### 2. Application Pipeline: `speri-app-pipeline`

| Property | Value |
|----------|-------|
| **Pipeline ID** | `695002a403c397c6c6bf6996` |
| **Type** | CI/CD + Deploy |
| **Tool** | Docker + ECS with speri-aws |
| **AWS Tool ID** | `694db37e487f729fe2a56cf1` |

**Portal URL**: https://portal.opsera.io/workflow/details/695002a403c397c6c6bf6996/summary

#### Workflow Steps:
1. **Docker Build** → Builds Docker image with timestamp tag
2. **Security Scan - Grype** → Container vulnerability scanning (HIGH threshold)
3. **Push to ECR** → Pushes image to AWS ECR
4. **Deploy to ECS** → Updates ECS service with new image
5. **Health Check & Validation** → Validates deployment success

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        INFRASTRUCTURE PIPELINE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌──────────────────┐       ┌──────────────────┐                      │
│   │  Route 53 Zone   │──────>│   ALB + TG       │                      │
│   │  (Created FIRST) │       │  (Created AFTER) │                      │
│   └──────────────────┘       └──────────────────┘                      │
│            │                          │                                 │
│            └──────────┬───────────────┘                                │
│                       ▼                                                 │
│            ┌──────────────────┐                                        │
│            │ DNS → ALB Alias  │                                        │
│            │  (R53 Record)    │                                        │
│            └──────────────────┘                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        APPLICATION PIPELINE                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌───────┐│
│   │ Docker  │───>│ Grype   │───>│ Push    │───>│ Deploy  │───>│Health ││
│   │ Build   │    │ Scan    │    │ to ECR  │    │ to ECS  │    │Check  ││
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘    └───────┘│
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Auto-Trigger Configuration

To enable automatic pipeline runs on code changes, configure a webhook in your Git repository:

### GitHub Webhook Setup

1. Go to your repository → Settings → Webhooks
2. Add webhook:
   - **Payload URL**: `https://api.opsera.io/v1/pipelines/695002a403c397c6c6bf6996/trigger`
   - **Content type**: `application/json`
   - **Events**: Push events, Pull request events

### GitLab Webhook Setup

1. Go to your project → Settings → Webhooks
2. Add webhook:
   - **URL**: `https://api.opsera.io/v1/pipelines/695002a403c397c6c6bf6996/trigger`
   - **Trigger**: Push events, Merge request events

---

## Terraform Files

Located in `terraform/aws/`:

| File | Purpose |
|------|---------|
| `main.tf` | Main infrastructure: R53, ALB, Security Groups, ACM |
| `variables.tfvars` | Environment-specific variables |

### Key R53 → ELB Configuration

```hcl
# Route 53 Zone created FIRST
resource "aws_route53_zone" "main" {
  name = var.domain_name
  # ...
}

# ALB created AFTER R53 Zone (depends_on)
resource "aws_lb" "main" {
  # ...
  depends_on = [aws_route53_zone.main]
}

# DNS Record points R53 → ALB
resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.main.zone_id
  alias {
    name    = aws_lb.main.dns_name
    zone_id = aws_lb.main.zone_id
  }
}
```

---

## Running Pipelines

### Via Opsera Portal
1. Navigate to pipeline URL
2. Click "Run Pipeline"
3. Select branch and confirm

### Via Opsera API
```bash
# Run Infrastructure Pipeline
curl -X POST "https://api.opsera.io/v2/actions" \
  -H "Authorization: Bearer $OPSERA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "run",
    "type": "pipeline",
    "version": 1,
    "target": ["6950029403c397c6c6bf697f"]
  }'

# Run Application Pipeline
curl -X POST "https://api.opsera.io/v2/actions" \
  -H "Authorization: Bearer $OPSERA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "run",
    "type": "pipeline",
    "version": 1,
    "target": ["695002a403c397c6c6bf6996"]
  }'
```

---

## speri-aws Tool Configuration

| Property | Value |
|----------|-------|
| **Tool ID** | `694db37e487f729fe2a56cf1` |
| **Owner** | srinivas@opsera.us |
| **Used By** | Both Infrastructure and Application pipelines |

---

<div align="center">

```
    .  ,
    |\/|
    bd "  Powered by @opsera
         Unified DevOps Platform
         opsera.io
```

</div>


