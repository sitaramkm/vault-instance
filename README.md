# Vault Demo Instance (AWS)

This repository provisions a **single-instance HashiCorp Vault** on AWS,
secured with HTTPS via an Application Load Balancer and integrated with
**CyberArk Secrets Hub** using JWT authentication.

It is designed for **demos, integrations, and validation**, not
production.

------------------------------------------------------------------------

## Prerequisites

-   AWS CLI v2
-   Terraform \>= 1.5
-   `jq`, `curl`
-   HashiCorp `vault` CLI
-   An AWS account with permissions for:
    -   EC2
    -   ELB / ALB
    -   ACM
    -   Route53
    -   SSM Parameter Store

------------------------------------------------------------------------

## Repository Structure

    .
    ├── common.env.example
    ├── secrets-hub.env.example
    ├── terraform.tfvars.example
    ├── helper/
    │   └── vault.sh
    ├── scripts/
    │   ├── tokens.sh
    │   └── seed_vault.sh
    └── terraform/

------------------------------------------------------------------------

## Initial Setup

### 1. Configure Environment

Copy the example file:

``` bash
cp common.env.example common.env
```

Edit `common.env` and set:

``` bash
RESOURCE_PREFIX="ski-07"
TF_VAR_owner=<your-name-for-resource-tag>

AWS_PROFILE=<your-aws-profile>
AWS_REGION=<your-aws-profile>

# Route53 / DNS
TF_VAR_zone_id=<your-Route53-zone-id>
TF_VAR_domain_name=${RESOURCE_PREFIX}.<your-domain>
```

These values determine how Vault is exposed and identified.

This prefix is used consistently for: - AWS resources - Vault mounts -
Vault auth paths - SSM parameters

> `common.env` is gitignored and should **not** be committed.

------------------------------------------------------------------------

### 2. Configure Terraform Variables

Copy the example file:

``` bash
cp terraform.tfvars.example terraform.tfvars
```

(Optional) Update the following :

-   **Tags** (environment, etc.)

Provide additional tags if you wish or set other values

------------------------------------------------------------------------

## Create the Vault Instance

Run:

``` bash
./helper/vault.sh create
```

This will:

-   Provision AWS infrastructure
-   Create an ALB with HTTPS
-   Restrict HTTPS access to your **current public IP**
-   Write Vault connection details to `vault_info.env`

By default only your local IP is allowed HTTPS access. 
SSH is not allowed. Use Systems Manager to connect to the instance

------------------------------------------------------------------------

## Allow Additional CIDRs

To allow access from another network:

``` bash
./helper/vault.sh allow <CIDR>
```

Example:

``` bash
./helper/vault.sh allow 10.20.30.0/24
OR
./helper/vault.sh allow 0.0.0.0/0
```

This updates the ALB security group via Terraform. 

------------------------------------------------------------------------

## Retrieve the Vault Root Token

Run:

``` bash
./helper/vault.sh get-token
```

This retrieves the Vault root token from AWS SSM Parameter Store and
writes it to:

``` bash
vault_info.env
```

To load it into your shell:

``` bash
source vault_info.env
```

------------------------------------------------------------------------

## Create Sample Secrets (for Secrets Hub Discovery)

Before seeding:

-   Ensure `secrets-hub.env` exists and is configured

### 1. Configure Secrets Hub Integration

If you plan to register Vault with CyberArk Secrets Hub:

``` bash
cp secrets-hub.env.example secrets-hub.env
```

Update values according to your Secrets Hub tenant.

> This file is **not required** to create the Vault instance itself,
> only for seeding and registration.

------------------------------------------------------------------------

Then run:

``` bash
./helper/vault.sh create-sample-secrets
```

This will:

-   Enable a dedicated KV v2 mount
-   Configure JWT authentication
-   Create Vault policies and roles
-   Create sample secrets
-   Print values required to register Vault in CyberArk Secrets Hub

Use the printed output when adding a new secrets store in Secrets Hub.

------------------------------------------------------------------------

## Destroy the Environment

When finished:

``` bash
./helper/vault.sh destroy
```

This will:

-   Destroy all AWS infrastructure
-   Remove SSM parameters created during bootstrap
-   Clean up local Terraform artifacts

------------------------------------------------------------------------

## Notes 

-   Single-node Vault
-   Root token is used for demo purposes
-   Not intended for production workloads
-   HTTPS access is intentionally restricted

------------------------------------------------------------------------

## Typical Demo Flow

1.  `./helper/vault.sh create`
2.  `./helper/vault.sh get-token`
3.  (Optional) `./helper/vault.sh allow <CIDR>`
4.  `./helper/vault.sh create-sample-secrets`
5.  Register Vault in CyberArk Secrets Hub
6.  Discover secrets

------------------------------------------------------------------------

## Cleanup Reminder

Always run `./helper/vault.sh destroy` when done to avoid orphaned AWS
resources.
