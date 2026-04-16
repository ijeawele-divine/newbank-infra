# NewBank Digital Banking Platform - Infrastructure

This repository contains the Terraform configuration that provisions the core AWS infrastructure for the NewBank Digital Banking Platform. It covers networking, compute, databases, caching, and messaging for a microservices-based banking application designed to serve 50,000 to 500,000 active users.

---
<img width="5516" height="1906" alt="newbank-architecture-diagram drawio" src="https://github.com/user-attachments/assets/998233ae-c085-4c57-914e-13e70a9a83b0" />

## Architecture Overview

The infrastructure is organized into three network layers inside a single VPC across two Availability Zones:

- **Public layer** - API Gateway, Application Load Balancer, NAT Gateways, Internet Gateway
- **Private layer** - ECS Fargate cluster running all 6 microservices and the Anti-Corruption Layer service
- **Data layer** - Aurora PostgreSQL cluster, ElastiCache Redis cluster, DynamoDB tables

Async communication between services is handled through an SNS + SQS fan-out pattern. Each downstream service has its own SQS queue subscribed to the relevant SNS topic. Dead Letter Queues are configured on all SQS queues to catch failed messages.

```
Internet
    |
API Gateway + ALB          [Public Subnets - AZ-A, AZ-B]
    |
ECS Fargate Cluster        [Private Subnets - AZ-A, AZ-B]
  - Auth Service
  - Account Service
  - Transfer Service
  - Loan Service
  - Notification Service
  - Audit Service
  - ACL Service (Legacy Integration)
    |
Aurora PostgreSQL           [Data Subnets - AZ-A, AZ-B]
ElastiCache Redis
DynamoDB
```

---

## Prerequisites

Before deploying this infrastructure you need the following installed and configured:

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) >= 2.0
- An AWS account with permissions to create VPC, ECS, RDS, ElastiCache, DynamoDB, SNS, SQS, IAM, and S3 resources
- AWS credentials configured locally

To configure your AWS credentials run:

```bash
aws configure
```

You will be prompted for your Access Key ID, Secret Access Key, region, and output format. Use `eu-north-1` as the region to match this configuration.

---

## Project Structure

```
newbank-infra/
├── backend.tf              # Remote state configuration (S3 + lockfile)
├── main.tf                 # Root module - calls all child modules
├── variables.tf            # Root variable definitions
├── outputs.tf              # Root outputs
├── terraform.tfvars        # Variable values (do not commit passwords to git)
├── bootstrap.sh            # One-time script to create S3 state bucket
├── README.md
└── modules/
    ├── vpc/                # VPC, subnets, route tables, IGW, NAT Gateways
    ├── security_groups/    # All security groups and rules
    ├── rds/                # Aurora PostgreSQL cluster and instances
    ├── elasticache/        # ElastiCache Redis replication group
    ├── messaging/          # SNS topics, SQS queues, Dead Letter Queues
    └── ecs/                # ECS cluster, task definitions, services, ALB, IAM
```

---

## Module Descriptions

### vpc
Provisions the VPC with 6 subnets across 2 Availability Zones - 2 public, 2 private, and 2 data subnets. Creates an Internet Gateway for public subnet routing and one NAT Gateway per AZ for private subnet outbound access. Route tables are properly associated so traffic flows through the correct gateways per subnet type.

### security_groups
Creates all four security groups - ALB, ECS, RDS, and ElastiCache - as empty resources first, then attaches rules separately using `aws_security_group_rule`. This pattern avoids circular dependency errors that occur when security groups reference each other inline. Each layer only accepts inbound traffic from the layer directly above it.

### rds
Provisions an Aurora PostgreSQL cluster with one instance per Availability Zone for high availability. Deletion protection and automated backups with a 7-day retention window are enabled. The cluster is placed in the data subnets and only accepts connections from the ECS security group on port 5432.

### elasticache
Provisions an ElastiCache Redis replication group with automatic failover and Multi-AZ enabled. Transit and at-rest encryption are both enabled. Used by the Auth Service for session token and JWT storage.

### messaging
Provisions the SNS topic for transfer events and SQS queues for the Notification and Audit services. Each queue has a corresponding Dead Letter Queue configured with a maximum receive count of 3. SNS-to-SQS subscriptions and queue policies are included so that SNS can write to both queues.

### ecs
Provisions the ECS Fargate cluster, IAM execution and task roles, Application Load Balancer, target groups, task definitions, and ECS services. Uses `for_each` over a services map variable so all 6 microservices are provisioned from a single set of resource blocks. CloudWatch log groups are configured per service for centralized logging.

---

## How to Deploy

### Step 1 - Bootstrap the remote state backend

This only needs to be run once. It creates the S3 bucket and configures it with versioning, encryption, and public access blocking.

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

### Step 2 - Initialise Terraform

```bash
terraform init
```

This connects to the S3 backend and downloads the AWS provider.

### Step 3 - Review the plan

```bash
terraform plan
```

Review the output carefully before applying. Confirm the resource count matches what you expect. No infrastructure is created at this step.

### Step 4 - Apply

```bash
terraform apply
```

Type `yes` when prompted. Provisioning takes approximately 15 to 20 minutes because Aurora and ElastiCache clusters take time to become available.

---

## Configuration

All variable values are set in `terraform.tfvars`. The key variables are:

| Variable | Description | Example |
|---|---|---|
| `project_name` | Used in all resource names and tags | `newbank` |
| `environment` | Deployment environment | `prod` |
| `aws_region` | AWS region to deploy into | `eu-north-1` |
| `availability_zones` | List of AZs for multi-AZ deployment | `["eu-north-1a", "eu-north-1b"]` |
| `database_password` | Aurora master password | Keep out of git |
| `services` | Map of all microservices with CPU, memory, image, and desired count | See tfvars |

### Sensitive Variables

Database credentials should never be committed to git. For production use, store them in AWS Secrets Manager or pass them in at apply time:

```bash
terraform apply -var="database_password=YourSecurePassword"
```

---

## State Management

Remote state is stored in S3 at `newbank-terraform-state/prod/terraform.tfstate`. State locking uses the S3 native lockfile mechanism (`use_lockfile = true`) to prevent multiple engineers from running simultaneous applies. The state bucket has versioning enabled so previous state versions can be recovered if corruption occurs.

If you need to work across multiple environments, use separate state keys:

```
prod/terraform.tfstate
staging/terraform.tfstate
dev/terraform.tfstate
```

---

## Tagging Convention

Every resource is tagged with at minimum:

```hcl
tags = {
  Name        = "${project_name}-resource-name"
  Environment = var.environment
  Project     = var.project_name
}
```

This enables cost allocation by environment and project in AWS Cost Explorer, and satisfies audit requirements for identifying which resources belong to which system.

---

## How to Destroy

To tear down all infrastructure:

```bash
terraform destroy
```

Note: The Aurora cluster has `deletion_protection = true` and the DynamoDB audit table has `deletion_protection_enabled = true`. These must be disabled manually in the AWS console or by updating the Terraform configuration before destroy will succeed. This is intentional to prevent accidental deletion of financial and compliance data.

---

## Estimated Monthly Cost

These are approximate figures for the `eu-north-1` region at the configured instance sizes:

| Resource | Approx Monthly Cost |
|---|---|
| Aurora PostgreSQL (2 x db.r6g.large) | ~$200 |
| ElastiCache Redis (2 x cache.t3.medium) | ~$60 |
| ECS Fargate (6 services, 2 tasks each) | ~$80 |
| NAT Gateways (2) | ~$65 |
| Application Load Balancer | ~$20 |
| SQS + SNS | ~$5 |
| **Total estimate** | **~$430/month** |

Costs will scale with traffic. Aurora and ElastiCache are the largest fixed costs.
