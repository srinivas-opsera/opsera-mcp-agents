---
name: slack-notifications
description: |
  Reusable Slack notification integration for CI/CD workflows. Supports configurable 
  notification scopes, triggers (success/failure/both), and channels. Integrates with
  all Opsera MCP tools including AWS EKS deployments, security scans, and DORA metrics.
  Powered by Opsera - The Unified DevOps Platform.
metadata:
  skillport:
    category: devops
    tags:
      - slack
      - notifications
      - cicd
      - github-actions
      - alerting
      - observability
      - opsera
    severity: enhancement
    version: 1.0.0
    date: 2026-01-13
---

# Slack Notifications Skill

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║     ██████╗ ██████╗ ███████╗███████╗██████╗  █████╗                          ║
║    ██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗                         ║
║    ██║   ██║██████╔╝███████╗█████╗  ██████╔╝███████║                         ║
║    ██║   ██║██╔═══╝ ╚════██║██╔══╝  ██╔══██╗██╔══██║                         ║
║    ╚██████╔╝██║     ███████║███████╗██║  ██║██║  ██║                         ║
║     ╚═════╝ ╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝                         ║
║                                                                               ║
║                    ━━━ UNIFIED DEVOPS PLATFORM ━━━                           ║
║                                                                               ║
║               Slack Notifications | CI/CD | GitHub Actions                    ║
║                                                                               ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  Version: 1.0.0                           Powered by Opsera                  ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

---

## 📋 Overview

This skill provides a reusable pattern for integrating Slack notifications into GitHub Actions workflows. It supports configurable notification scopes, triggers, and channels.

**Use Cases:**
- Deployment status notifications (EKS, Kubernetes, Docker)
- Security scan results alerts
- DORA metrics reporting
- Pipeline failure notifications
- Infrastructure changes alerts

---

## 🔴 Problem Statement

When deploying applications via GitOps workflows, teams need real-time visibility into deployment status. Without notifications:
- Teams discover failures only when checking GitHub manually
- No immediate awareness of successful deployments
- Lack of audit trail for deployment events
- Delayed incident response

---

## ✅ Solution

Integrate Slack notifications using the official `slackapi/slack-github-action` with:
- Configurable notification triggers (success, failure, or both)
- Rich message formatting with deployment context
- Direct links to workflow runs
- Environment and branch information

---

## 🔧 Prerequisites

### 1. Create Slack Webhook

1. Go to https://api.slack.com/apps
2. Create a new app or select existing
3. Navigate to **Incoming Webhooks**
4. Activate incoming webhooks
5. Click **Add New Webhook to Workspace**
6. Select the target channel (e.g., `#deployments`)
7. Copy the webhook URL

### 2. Add GitHub Secret

Add the webhook URL as a repository secret:

```bash
# Secret Name: SLACK_WEBHOOK_URL
# Secret Value: <your-webhook-url-from-slack>
```

**Via GitHub CLI:**
```bash
gh secret set SLACK_WEBHOOK_URL --body "<your-webhook-url>"
```

---

## 📝 Implementation

### Workflow Input (Optional Toggle)

Add to your workflow's `workflow_dispatch` inputs:

```yaml
on:
  workflow_dispatch:
    inputs:
      enable_slack_notifications:
        description: 'Enable Slack notifications'
        type: boolean
        default: true
```

### Notification Step Templates

#### Template 1: Both Success & Failure

```yaml
- name: Slack Notification
  if: ${{ inputs.enable_slack_notifications && (success() || failure()) }}
  uses: slackapi/slack-github-action@v1.25.0
  with:
    channel-id: '#your-channel'
    payload: |
      {
        "text": "Deployment *${{ job.status }}* for `${{ env.APP_NAME }}`",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Deployment Status: ${{ github.job }}*\n• App: `${{ env.APP_NAME }}`\n• Env: `${{ env.APP_ENV }}`\n• Status: *${{ job.status }}*\n• Branch: `${{ github.ref_name }}`\n• Workflow: <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Run>"
            }
          }
        ]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

#### Template 2: Success Only

```yaml
- name: Slack Notification (Success)
  if: ${{ inputs.enable_slack_notifications && success() }}
  uses: slackapi/slack-github-action@v1.25.0
  with:
    channel-id: '#your-channel'
    payload: |
      {
        "text": "✅ Deployment *succeeded* for `${{ env.APP_NAME }}`",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*✅ Deployment Succeeded*\n• App: `${{ env.APP_NAME }}`\n• Env: `${{ env.APP_ENV }}`\n• Branch: `${{ github.ref_name }}`\n• Commit: `${{ github.sha }}`\n• Workflow: <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Run>"
            }
          }
        ]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

#### Template 3: Failure Only

```yaml
- name: Slack Notification (Failure)
  if: ${{ inputs.enable_slack_notifications && failure() }}
  uses: slackapi/slack-github-action@v1.25.0
  with:
    channel-id: '#your-channel'
    payload: |
      {
        "text": "❌ Deployment *failed* for `${{ env.APP_NAME }}`",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*❌ Deployment Failed*\n• App: `${{ env.APP_NAME }}`\n• Env: `${{ env.APP_ENV }}`\n• Branch: `${{ github.ref_name }}`\n• Commit: `${{ github.sha }}`\n• Workflow: <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Run>\n• *Action Required:* Check logs and fix the issue"
            }
          }
        ]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## 🎯 Configuration Schema

When integrating with MCP tools, collect these inputs:

```json
{
  "slack_notifications": {
    "enabled": {
      "type": "boolean",
      "description": "Enable Slack notifications?",
      "default": false
    },
    "channel": {
      "type": "string",
      "description": "Slack channel (e.g., #deployments)",
      "required_if": "enabled == true"
    },
    "scope": {
      "type": "string",
      "enum": ["all_jobs", "single_step"],
      "description": "Notify for all jobs or single step?",
      "default": "all_jobs"
    },
    "step_name": {
      "type": "string",
      "description": "Which step to notify for?",
      "required_if": "scope == 'single_step'"
    },
    "trigger": {
      "type": "string",
      "enum": ["success", "failure", "both"],
      "description": "When to send notification?",
      "default": "both"
    }
  }
}
```

---

## 🔄 MCP Tool Integration Pattern

When an Opsera MCP tool creates a workflow, follow this pattern:

### Step 1: Ask User About Notifications

```
Do you want Slack notifications for this deployment? (yes/no)
```

### Step 2: If Yes, Collect Configuration

```
Slack Configuration:
1. Channel: #deployments
2. Scope: All jobs / Single step
3. Step name (if single step): infrastructure
4. Trigger: Success / Failure / Both
```

### Step 3: Generate Workflow with Notifications

Based on user input, inject the appropriate notification step into the generated workflow YAML.

### Step 4: Remind About Secrets

```
⚠️ Required Secret: SLACK_WEBHOOK_URL
Add your Slack incoming webhook URL as a repository secret.
```

---

## 📊 Message Templates By Event Type

### Deployment Events

**Success:**
```json
{
  "text": "✅ Deployment succeeded",
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "✅ Deployment Successful" }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*App:*\n{{APP_NAME}}" },
        { "type": "mrkdwn", "text": "*Environment:*\n{{APP_ENV}}" },
        { "type": "mrkdwn", "text": "*Branch:*\n{{BRANCH}}" },
        { "type": "mrkdwn", "text": "*Commit:*\n{{SHORT_SHA}}" }
      ]
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "🔗 <{{WORKFLOW_URL}}|View Workflow>" }
    }
  ]
}
```

**Failure:**
```json
{
  "text": "❌ Deployment failed",
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "❌ Deployment Failed" }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*App:*\n{{APP_NAME}}" },
        { "type": "mrkdwn", "text": "*Environment:*\n{{APP_ENV}}" },
        { "type": "mrkdwn", "text": "*Branch:*\n{{BRANCH}}" },
        { "type": "mrkdwn", "text": "*Commit:*\n{{SHORT_SHA}}" }
      ]
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "⚠️ *Action Required:* Check logs and fix the issue" }
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "🔗 <{{WORKFLOW_URL}}|View Workflow Logs>" }
    }
  ]
}
```

### Security Scan Events

```json
{
  "text": "🔒 Security Scan Complete",
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "🔒 Security Scan Results" }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*Repository:*\n{{REPO_NAME}}" },
        { "type": "mrkdwn", "text": "*Vulnerabilities:*\n{{VULN_COUNT}}" },
        { "type": "mrkdwn", "text": "*Critical:*\n{{CRITICAL_COUNT}}" },
        { "type": "mrkdwn", "text": "*High:*\n{{HIGH_COUNT}}" }
      ]
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": "🔗 <{{SCAN_REPORT_URL}}|View Full Report>" }
    }
  ]
}
```

### Infrastructure Events

```json
{
  "text": "🏗️ Infrastructure Update",
  "blocks": [
    {
      "type": "header",
      "text": { "type": "plain_text", "text": "🏗️ Infrastructure Update" }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*Action:*\n{{TF_ACTION}}" },
        { "type": "mrkdwn", "text": "*Environment:*\n{{ENV}}" },
        { "type": "mrkdwn", "text": "*Resources Added:*\n{{ADDED}}" },
        { "type": "mrkdwn", "text": "*Resources Changed:*\n{{CHANGED}}" },
        { "type": "mrkdwn", "text": "*Resources Destroyed:*\n{{DESTROYED}}" }
      ]
    }
  ]
}
```

---

## 🛠️ Integration with Opsera MCP Tools

### AWS EKS Container Deployment

When using `opsera_container_eks` or `opsera_unified_aws_container_gitops`, Slack notifications can be configured at:

1. **Infrastructure Phase**: Alert when Terraform applies complete
2. **Build Phase**: Alert when Docker images are pushed to ECR
3. **Deploy Phase**: Alert when ArgoCD syncs complete
4. **Verification Phase**: Alert when endpoint is accessible

**Example integration in workflow:**

```yaml
jobs:
  infrastructure:
    # ... terraform steps ...
    steps:
      - name: Slack - Infrastructure Complete
        if: ${{ inputs.enable_slack_notifications && success() }}
        uses: slackapi/slack-github-action@v1.25.0
        with:
          payload: |
            {
              "text": "🏗️ Infrastructure ready for `${{ env.APP_NAME }}`",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*🏗️ Infrastructure Ready*\n• Cluster: `${{ env.CLUSTER_NAME }}`\n• Region: `${{ env.AWS_REGION }}`\n• VPC: Created/Updated"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

  deploy:
    # ... deployment steps ...
    steps:
      - name: Slack - Deployment Complete
        if: ${{ inputs.enable_slack_notifications && (success() || failure()) }}
        uses: slackapi/slack-github-action@v1.25.0
        with:
          payload: |
            {
              "text": "${{ job.status == 'success' && '✅' || '❌' }} Deployment ${{ job.status }} for `${{ env.APP_NAME }}`",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*${{ job.status == 'success' && '✅ Deployment Successful' || '❌ Deployment Failed' }}*\n• App: `${{ env.APP_NAME }}`\n• Endpoint: `https://${{ env.APP_NAME }}.your-domain.com`\n• Workflow: <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Run>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### Security Scans

When using `opsera_security_scan`, add notifications for scan completion:

```yaml
- name: Slack - Security Scan Results
  if: ${{ inputs.enable_slack_notifications }}
  uses: slackapi/slack-github-action@v1.25.0
  with:
    payload: |
      {
        "text": "🔒 Security scan completed for ${{ github.repository }}",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn", 
              "text": "*🔒 Security Scan Results*\n• Critical: ${{ env.CRITICAL_COUNT || '0' }}\n• High: ${{ env.HIGH_COUNT || '0' }}\n• Medium: ${{ env.MEDIUM_COUNT || '0' }}\n• Status: ${{ env.SCAN_STATUS }}"
            }
          }
        ]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### DORA Metrics

When using `opsera_dora_metrics`, send periodic reports:

```yaml
- name: Slack - DORA Metrics Report
  if: ${{ inputs.enable_slack_notifications }}
  uses: slackapi/slack-github-action@v1.25.0
  with:
    payload: |
      {
        "text": "📊 DORA Metrics Report",
        "blocks": [
          {
            "type": "header",
            "text": { "type": "plain_text", "text": "📊 DORA Metrics Report" }
          },
          {
            "type": "section",
            "fields": [
              { "type": "mrkdwn", "text": "*Deployment Frequency:*\n${{ env.DEPLOY_FREQ }}" },
              { "type": "mrkdwn", "text": "*Lead Time:*\n${{ env.LEAD_TIME }}" },
              { "type": "mrkdwn", "text": "*Change Failure Rate:*\n${{ env.CFR }}" },
              { "type": "mrkdwn", "text": "*MTTR:*\n${{ env.MTTR }}" }
            ]
          },
          {
            "type": "section",
            "text": { "type": "mrkdwn", "text": "*Performance Category:* ${{ env.DORA_CATEGORY }}" }
          }
        ]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## 🛡️ Best Practices

1. **Use Workflow Input Toggle**: Allow users to enable/disable notifications per run
2. **Include Direct Links**: Always link to the workflow run for quick access
3. **Context-Rich Messages**: Include app name, environment, branch, and commit
4. **Failure Emphasis**: Make failure notifications stand out with clear action items
5. **Channel Separation**: Consider separate channels for dev/staging/prod
6. **Rate Limiting**: Avoid notification fatigue by being selective about what triggers notifications
7. **Thread Replies**: Use Slack threads for related notifications in the same deployment

---

## 🔐 Security Considerations

1. **Webhook URL Security**: Store webhook URLs ONLY as GitHub Secrets, never in code
2. **Channel Permissions**: Ensure the webhook only has access to intended channels
3. **Message Content**: Don't include sensitive data (secrets, tokens, passwords) in messages
4. **Audit Trail**: Slack messages serve as deployment audit trail - include relevant context

---

## 📦 Required GitHub Secrets

| Secret Name | Description | Required |
|-------------|-------------|----------|
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL | Yes |

---

## 🔗 Related Skills

- **unified-aws-container-gitops**: Full AWS EKS deployment with GitOps
- **terraform-eks-deployment**: Terraform EKS best practices
- **argocd-multi-tenant-gitops**: Multi-tenant ArgoCD setup

---

## 📚 References

- [Slack GitHub Action](https://github.com/slackapi/slack-github-action)
- [Slack Block Kit Builder](https://app.slack.com/block-kit-builder)
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks)
- [GitHub Actions - Using secrets](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)

---

## 📝 Changelog

### Version 1.0.0 (2026-01-13)
- Initial release
- Support for success/failure/both triggers
- Integration patterns for AWS EKS deployments
- Integration patterns for security scans
- Integration patterns for DORA metrics
- Rich message templates with Block Kit

