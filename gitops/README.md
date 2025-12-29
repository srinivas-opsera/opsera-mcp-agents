# Multi-Tenant GitOps Architecture

This directory contains the GitOps configuration for the Opsera MCP Agents platform.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TENANTS                                         │
├──────────────────────┬──────────────────────┬──────────────────────────────┤
│      Tenant A        │      Tenant B        │         Tenant C             │
│  ┌────┐ ┌────┐ ┌────┐│  ┌────┐ ┌────┐      │     ┌────┐                    │
│  │App1│ │App2│ │App3││  │App1│ │App2│      │     │App1│                    │
│  └────┘ └────┘ └────┘│  └────┘ └────┘      │     └────┘                    │
└──────────────────────┴──────────────────────┴──────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ENDPOINTS                                         │
│  appA1-dev.agent.opsera.io    appB1-dev.agent.opsera.io    appC1.agent...   │
│  appA1-stg.agent.opsera.io    appB1-stg.agent.opsera.io                     │
│  appA1.agent.opsera.io        appB1.agent.opsera.io                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ARGO APPLICATIONS                                   │
│  ┌─────────────────────────────┐    ┌─────────────────────────────┐         │
│  │      US Region              │    │      EU Region              │         │
│  │  AppA-1-Dev, AppA-1-Stg     │    │  AppA-1-ue, AppA-1-eu       │         │
│  │  AppA-2-Dev, AppA-2-Stg     │    │  AppA-2-ue, AppA-2-eu       │         │
│  │  AppB-1-Dev, AppB-1-Stg     │    │  AppB-1-ue, AppB-1-eu       │         │
│  └─────────────────────────────┘    └─────────────────────────────┘         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         K8S CLUSTERS                                         │
│  ┌─────────────────────────────┐    ┌─────────────────────────────┐         │
│  │      US Region              │    │      EU Region              │         │
│  │  K8s-A-Dev, K8s-A-Stage     │    │  K8s-A-Prod-ue-1, eu-1      │         │
│  │  K8s-B-Dev, K8s-B-Stage     │    │  K8s-B-Prod-ue-1, eu-1      │         │
│  │  K8s-C-Dev, K8s-C-Stage     │    │  K8s-C-Prod-ue-1, eu-1      │         │
│  └─────────────────────────────┘    └─────────────────────────────┘         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
gitops/
├── argocd/                    # ArgoCD installation and config
│   ├── install.yaml           # ArgoCD installation manifest
│   ├── app-of-apps.yaml       # Root application
│   └── applicationsets/       # ApplicationSet definitions
│       ├── tenant-apps.yaml   # Generates apps per tenant/env/region
│       └── infra-apps.yaml    # Infrastructure apps (ingress, etc.)
│
├── clusters/                  # Cluster-specific configurations
│   ├── us-west-2/            # US Region clusters
│   │   ├── dev/              # Development cluster
│   │   └── stg/              # Staging cluster
│   └── eu-west-1/            # EU Region clusters
│       ├── prod-ue/          # Production US-East
│       └── prod-eu/          # Production EU
│
├── tenants/                   # Tenant configurations
│   ├── tenant-a/
│   │   ├── apps/             # Tenant A's applications
│   │   │   ├── app1/
│   │   │   ├── app2/
│   │   │   └── app3/
│   │   └── config/           # Tenant-specific config
│   ├── tenant-b/
│   │   ├── apps/
│   │   │   ├── app1/
│   │   │   └── app2/
│   │   └── config/
│   └── tenant-c/
│       ├── apps/
│       │   └── app1/
│       └── config/
│
├── base/                      # Base Kustomize templates
│   ├── namespace/
│   ├── deployment/
│   ├── service/
│   └── ingress/
│
└── infra/                     # Infrastructure components
    ├── ingress-nginx/
    ├── cert-manager/
    └── external-dns/
```

## Environments

| Environment | Region     | Cluster Name       | Purpose          |
|-------------|------------|-------------------|------------------|
| dev         | us-west-2  | opsera-mcp-dev    | Development      |
| stg         | us-west-2  | opsera-mcp-stg    | Staging          |
| prod-ue     | us-east-1  | opsera-mcp-ue-1   | Production US    |
| prod-eu     | eu-west-1  | opsera-mcp-eu-1   | Production EU    |

## Tenants

| Tenant   | Apps                          | Namespaces                |
|----------|-------------------------------|---------------------------|
| tenant-a | app1, app2, app3              | tenant-a-{dev,stg,prod}   |
| tenant-b | app1, app2                    | tenant-b-{dev,stg,prod}   |
| tenant-c | app1                          | tenant-c-{dev,stg,prod}   |

## Endpoints

Format: `{app}-{env}.agent.opsera.io`

Examples:
- `app1-dev.agent.opsera.io` → Tenant A App1 Dev
- `app1-stg.agent.opsera.io` → Tenant A App1 Staging
- `app1.agent.opsera.io` → Tenant A App1 Production

