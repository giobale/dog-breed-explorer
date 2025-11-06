# Secret Manager Setup with Terraform

## Overview

This guide explains how to set up Google Cloud Secret Manager using Terraform to securely store credentials needed for the dlt pipeline and GitHub Actions CI/CD workflows.

## Prerequisites

1. Google Cloud Project with billing enabled
2. Terraform installed (>= 1.0)
3. `gcloud` CLI installed and authenticated
4. Service account JSON key file for dlt pipeline
5. GitHub Actions service account created (see below)

### Authenticate Terraform with GCP

Before running Terraform commands, authenticate using Application Default Credentials:

```bash
gcloud auth application-default login
```

This allows Terraform to authenticate with GCP without explicitly passing credentials in the provider block.

## Secrets Stored

The Terraform configuration creates three secrets in Secret Manager:

1. **dlt-service-account-key**: Service account JSON key for BigQuery access
2. **dog-api-base-url**: Base URL for The Dog API
3. **dog-api-endpoint**: API endpoint path for dog breeds

## Setup Steps

### 1. Create GitHub Actions Service Account

Create a dedicated service account for GitHub Actions (separate from your dlt service account):

```bash
# Create the service account
gcloud iam service-accounts create github-actions \
  --project=pyne-de-assignemet \
  --display-name="GitHub Actions CI/CD"

# Grant Secret Manager access
gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### 2. Create secrets.tfvars File

Copy the example file and fill in your actual values:

```bash
cd infrastructure
cp secrets.tfvars.example secrets.tfvars
```

Edit `secrets.tfvars` and provide:
- Path to your service account JSON key file (relative to infrastructure directory)
- GitHub Actions service account email (from previous step)
- Dog API configuration (optional, defaults provided)

Example `secrets.tfvars`:
```hcl
service_account_key_path = "../pyne-de-assignemet-tf-service-account-key.json"
dog_api_base_url = "https://api.thedogapi.com/v1"
dog_api_endpoint = "breeds"
github_actions_service_account_email = "github-actions@pyne-de-assignemet.iam.gserviceaccount.com"
```

**IMPORTANT**: Never commit `secrets.tfvars` to Git. It's already in `.gitignore`.

### 3. Initialize Terraform

```bash
cd infrastructure
terraform init
```

This downloads the required providers and initializes the backend.

### 4. Review Changes

```bash
terraform plan -var-file="secrets.tfvars" \
  -var="project_id=YOUR_PROJECT_ID"
```

Review the resources that will be created:
- Secret Manager secrets
- IAM bindings for GitHub Actions service account

### 5. Apply Configuration

```bash
terraform apply -var-file="secrets.tfvars" \
  -var="project_id=YOUR_PROJECT_ID"
```

Type `yes` when prompted to create the resources.

### 6. Verify Secrets

```bash
gcloud secrets list --project=YOUR_PROJECT_ID

# View secret metadata (not the actual secret value)
gcloud secrets describe dlt-service-account-key --project=YOUR_PROJECT_ID
```

## Workload Identity Federation Setup

To allow GitHub Actions to authenticate without storing service account keys as GitHub secrets, set up Workload Identity Federation:

### 1. Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "github-actions-pool" \
  --project="YOUR_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

### 2. Create Workload Identity Provider

```bash
gcloud iam workload-identity-pools providers create-oidc "github-actions-provider" \
  --project="YOUR_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-actions-pool" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner=='YOUR_GITHUB_USERNAME_OR_ORG'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

### 3. Grant Service Account Access

```bash
# Get your GitHub Actions service account email from secrets.tfvars
# Replace YOUR_GITHUB_REPO with owner/repo format (e.g., myuser/dog-breed-explorer)

gcloud iam service-accounts add-iam-policy-binding \
  "github-actions-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --project="YOUR_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/YOUR_GITHUB_REPO"
```

### 4. Add GitHub Repository Secrets

In your GitHub repository, add these secrets (Settings > Secrets and variables > Actions):

```
GCP_PROJECT_ID=your-project-id
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider
GCP_SERVICE_ACCOUNT=github-actions-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

## How GitHub Actions Retrieves Secrets

The PR validation workflow (`.github/workflows/pr-validation.yml`) authenticates using Workload Identity and retrieves secrets:

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

- name: Retrieve secrets from Secret Manager
  run: |
    gcloud secrets versions access latest --secret="dlt-service-account-key" > /tmp/service-account.json
    echo "GOOGLE_APPLICATION_CREDENTIALS=/tmp/service-account.json" >> $GITHUB_ENV

    DOG_API_BASE_URL=$(gcloud secrets versions access latest --secret="dog-api-base-url")
    DOG_API_ENDPOINT=$(gcloud secrets versions access latest --secret="dog-api-endpoint")
    echo "DOG_API_BASE_URL=$DOG_API_BASE_URL" >> $GITHUB_ENV
    echo "DOG_API_ENDPOINT=$DOG_API_ENDPOINT" >> $GITHUB_ENV
```

## Updating Secrets

To update secret values:

1. Edit `secrets.tfvars` with new values
2. Run `terraform apply -var-file="secrets.tfvars" -var="project_id=YOUR_PROJECT_ID"`

Terraform will update the secret versions automatically.

## Security Best Practices

1. **Never commit secrets.tfvars**: Already in `.gitignore`, but double-check
2. **Limit IAM permissions**: Only grant `secretAccessor` role to necessary service accounts
3. **Use Workload Identity**: Avoid storing long-lived service account keys in GitHub secrets
4. **Rotate credentials**: Periodically rotate service account keys and update secrets
5. **Audit access**: Review Secret Manager audit logs regularly

## Troubleshooting

### Error: Secret already exists

If secrets already exist from manual creation or bash script:

```bash
# Import existing secrets into Terraform state
terraform import -var-file="secrets.tfvars" \
  -var="project_id=YOUR_PROJECT_ID" \
  module.secret_manager.google_secret_manager_secret.dlt_service_account_key \
  projects/YOUR_PROJECT_ID/secrets/dlt-service-account-key
```

### Error: Permission denied when creating secrets

Ensure your authenticated user has the `roles/secretmanager.admin` role:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="user:your-email@example.com" \
  --role="roles/secretmanager.admin"
```

### GitHub Actions cannot access secrets

1. Verify Workload Identity Federation is configured correctly
2. Check that the service account has `secretAccessor` role (Terraform handles this)
3. Verify GitHub repository secrets are set correctly
4. Check that `attribute.repository_owner` condition matches your GitHub username/org

## Related Files

- `infrastructure/main.tf`: Root Terraform configuration
- `infrastructure/variables.tf`: Root-level variables
- `infrastructure/secrets.tfvars.example`: Template for secrets
- `infrastructure/modules/secret-manager/`: Secret Manager Terraform module
- `.github/workflows/pr-validation.yml`: PR validation workflow that uses secrets
