# Secrets Management and Authentication

## Overview

This document explains how secrets are stored, managed, and accessed across the entire platform, including local development, CI/CD pipelines, and cloud infrastructure. The system uses Google Cloud Secret Manager for centralized secret storage and Workload Identity Federation for secure, keyless authentication from GitHub Actions.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Secrets Storage                              │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │         Google Cloud Secret Manager (Centralized)              │ │
│  │  - dlt-service-account-key (JSON key for BigQuery access)     │ │
│  │  - dog-api-base-url (https://api.thedogapi.com/v1)            │ │
│  │  - dog-api-endpoint (breeds)                                   │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐          ┌────────────────┐         ┌─────────────────┐
│ Local Dev     │          │ GitHub Actions │         │ Cloud Run Jobs  │
│               │          │                │         │                 │
│ Auth: .env    │          │ Auth: Workload │         │ Auth: Service   │
│ with SA key   │          │ Identity Fed   │         │ Account         │
└───────────────┘          └────────────────┘         └─────────────────┘
```

---

## 1. Secret Storage in Google Cloud Secret Manager

### Secrets Stored

The platform stores three secrets in Secret Manager:

| Secret ID | Description | Used By |
|-----------|-------------|---------|
| `dlt-service-account-key` | Service account JSON key with BigQuery permissions | dlt pipeline (local, CI/CD, Cloud Run) |
| `dog-api-base-url` | Base URL for The Dog API | dlt pipeline |
| `dog-api-endpoint` | API endpoint path for dog breeds | dlt pipeline |

### Managing Secrets with Terraform

Secrets are provisioned and managed using Terraform in `infrastructure/modules/secret-manager/`:

```hcl
# infrastructure/modules/secret-manager/main.tf
resource "google_secret_manager_secret" "dlt_service_account_key" {
  secret_id = "dlt-service-account-key"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "dlt_service_account_key" {
  secret      = google_secret_manager_secret.dlt_service_account_key.id
  secret_data = var.service_account_key_content
}
```

### Creating/Updating Secrets

To deploy or update secrets:

```bash
cd infrastructure

# Create secrets.tfvars with your values
cat > secrets.tfvars <<EOF
service_account_key_path = "../keys/pyne-de-assignemet-dlt-sa-key.json"
dog_api_base_url = "https://api.thedogapi.com/v1"
dog_api_endpoint = "breeds"
github_actions_service_account_email = "github-actions@pyne-de-assignemet.iam.gserviceaccount.com"
EOF

# Apply Terraform
terraform init
terraform apply -var-file="secrets.tfvars" -var="project_id=pyne-de-assignemet"
```

### IAM Permissions for Secrets

The Terraform configuration automatically grants Secret Manager access to the GitHub Actions service account:

```hcl
resource "google_secret_manager_secret_iam_member" "dlt_service_account_key_accessor" {
  secret_id = google_secret_manager_secret.dlt_service_account_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.github_actions_service_account_email}"
}
```

---

## 2. GitHub Actions Authentication (Workload Identity Federation)

### How It Works

GitHub Actions uses **Workload Identity Federation** to authenticate with Google Cloud **without storing long-lived service account keys**. This is more secure than traditional key-based authentication.

#### Authentication Flow

```
1. GitHub Actions requests OIDC token from GitHub
        ▼
2. Token contains metadata (repository, actor, etc.)
        ▼
3. google-github-actions/auth exchanges OIDC token
   with Google Cloud STS (Security Token Service)
        ▼
4. STS validates token and returns short-lived credentials
        ▼
5. Credentials include impersonation URL for service account
        ▼
6. gcloud uses credentials to impersonate github-actions@...
        ▼
7. Impersonated service account accesses Secret Manager
```

### Required GCP Resources

#### 1. Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "github-actions-pool" \
  --project="pyne-de-assignemet" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

#### 2. Workload Identity Provider

```bash
gcloud iam workload-identity-pools providers create-oidc "github-actions-provider" \
  --project="pyne-de-assignemet" \
  --location="global" \
  --workload-identity-pool="github-actions-pool" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner=='giobale'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

**Important**: The `attribute-condition` restricts authentication to repositories owned by the specified GitHub user/org.

#### 3. Service Account

```bash
# Create service account
gcloud iam service-accounts create github-actions \
  --project=pyne-de-assignemet \
  --display-name="GitHub Actions CI/CD"

# Grant Secret Manager access
gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Grant BigQuery access (for PR dataset creation/cleanup)
gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/bigquery.admin"
```

#### 4. Workload Identity User Binding

**This is the critical step that enables impersonation:**

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --project="pyne-de-assignemet" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/120922532177/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/giobale/dog-breed-explorer"
```

This grants the GitHub repository (`giobale/dog-breed-explorer`) permission to impersonate the `github-actions` service account.

### GitHub Repository Secrets

Three secrets must be configured in the GitHub repository (Settings → Secrets and variables → Actions):

| Secret Name | Value | Example |
|-------------|-------|---------|
| `GCP_PROJECT_ID` | Google Cloud project ID | `pyne-de-assignemet` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full resource name of the WIF provider | `projects/120922532177/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider` |
| `GCP_SERVICE_ACCOUNT` | Service account email to impersonate | `github-actions@pyne-de-assignemet.iam.gserviceaccount.com` |

### Workflow Authentication Configuration

The `.github/workflows/pr-validation.yml` workflow authenticates as follows:

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
    create_credentials_file: true
    export_environment_variables: true

- name: Set up Cloud SDK
  uses: google-github-actions/setup-gcloud@v2
```

**What happens under the hood:**

1. The `auth` action creates a credentials file at a temporary path (e.g., `/home/runner/.../gha-creds-xxx.json`)
2. The credentials file is of type `external_account` with a `service_account_impersonation_url`
3. `GOOGLE_APPLICATION_CREDENTIALS` environment variable is set to the credentials file path
4. `gcloud` and Google Cloud client libraries automatically use these credentials
5. When accessing resources, the credentials trigger impersonation of the `github-actions` service account

### Retrieving Secrets in Workflows

After authentication, the workflow retrieves secrets from Secret Manager:

```yaml
- name: Retrieve secrets from Secret Manager
  id: secrets
  run: |
    # Retrieve service account key from Secret Manager
    gcloud secrets versions access latest --secret="dlt-service-account-key" --project=${{ secrets.GCP_PROJECT_ID }} > /tmp/service-account.json
    echo "GOOGLE_APPLICATION_CREDENTIALS=/tmp/service-account.json" >> $GITHUB_ENV

    # Retrieve environment variables from Secret Manager
    DOG_API_BASE_URL=$(gcloud secrets versions access latest --secret="dog-api-base-url" --project=${{ secrets.GCP_PROJECT_ID }})
    DOG_API_ENDPOINT=$(gcloud secrets versions access latest --secret="dog-api-endpoint" --project=${{ secrets.GCP_PROJECT_ID }})

    echo "DOG_API_BASE_URL=$DOG_API_BASE_URL" >> $GITHUB_ENV
    echo "DOG_API_ENDPOINT=$DOG_API_ENDPOINT" >> $GITHUB_ENV
```

**Important**: The workflow overwrites `GOOGLE_APPLICATION_CREDENTIALS` with the DLT service account key retrieved from Secret Manager. This is because the dlt pipeline needs to authenticate as the DLT service account (which has BigQuery permissions), not the GitHub Actions service account.

---

## 3. Local Development Authentication

### Setting Up Local Environment

For local development, create a `.env` file in the project root:

```bash
# .env
GOOGLE_APPLICATION_CREDENTIALS=keys/pyne-de-assignemet-dlt-sa-key.json
DOG_API_BASE_URL=https://api.thedogapi.com/v1
DOG_API_ENDPOINT=breeds
BIGQUERY_DATASET=dog_breeds_raw
GCP_PROJECT_ID=pyne-de-assignemet
```

The dlt pipeline's `config.py` loads these environment variables:

```python
from dotenv import load_dotenv

load_dotenv(dotenv_path=project_root / ".env")

api_base_url = os.getenv("DOG_API_BASE_URL")
api_endpoint = os.getenv("DOG_API_ENDPOINT")
bigquery_dataset = os.getenv("BIGQUERY_DATASET")
bigquery_project_id = os.getenv("GCP_PROJECT_ID")
```

### Authenticating Terraform Locally

Terraform uses Application Default Credentials (ADC) to authenticate with GCP:

```bash
gcloud auth application-default login
```

This creates credentials at `~/.config/gcloud/application_default_credentials.json` that Terraform uses automatically.

---

## 4. Cloud Run Jobs Authentication

When deployed to Cloud Run Jobs, the dlt container authenticates using:

1. **Service account attached to the Cloud Run Job** (configured in Terraform)
2. **Service account key from Secret Manager** (passed as environment variable or mounted secret)

The Cloud Run Job configuration would look like:

```hcl
resource "google_cloud_run_v2_job" "dlt_ingestion" {
  name     = "dlt-dog-breeds-ingestion"
  location = var.region

  template {
    template {
      service_account = var.service_account_email

      containers {
        image = var.container_image

        env {
          name  = "GOOGLE_APPLICATION_CREDENTIALS"
          value = "/secrets/service-account.json"
        }

        volume_mounts {
          name       = "secret-volume"
          mount_path = "/secrets"
        }
      }

      volumes {
        name = "secret-volume"
        secret {
          secret       = "dlt-service-account-key"
          default_mode = 0444
        }
      }
    }
  }
}
```

---

## 5. Security Best Practices

### Do's

✅ **Use Workload Identity Federation** for GitHub Actions (no long-lived keys stored in GitHub)
✅ **Store all secrets in Secret Manager** (centralized, auditable, versioned)
✅ **Use least-privilege IAM roles** (grant only necessary permissions)
✅ **Add `.env` and `secrets.tfvars` to `.gitignore`** (prevent accidental commits)
✅ **Rotate service account keys periodically** (update in Secret Manager via Terraform)
✅ **Use PR-specific datasets** in CI/CD (isolate test data, automatic cleanup)
✅ **Enable audit logging** for Secret Manager access

### Don'ts

❌ **Never commit service account keys** to Git repositories
❌ **Never store secrets in GitHub repository secrets** (except WIF configuration values)
❌ **Never grant overly broad IAM roles** (e.g., `roles/owner`, `roles/editor`)
❌ **Never disable impersonate_service_account** in gcloud (it's required for WIF)
❌ **Never share service account keys** via email, Slack, etc.

---

## 6. Troubleshooting

### Error: Permission 'iam.serviceAccounts.getAccessToken' denied

**Symptom**: GitHub Actions fails with impersonation error when accessing Secret Manager.

**Cause**: Workload Identity principal doesn't have permission to impersonate the service account.

**Solution**: Grant `roles/iam.workloadIdentityUser` to the repository:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --project="pyne-de-assignemet" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/GITHUB_USER/REPO_NAME"
```

### Error: Secret not found

**Symptom**: `gcloud secrets versions access` fails with "NOT_FOUND" error.

**Cause**: Secret doesn't exist in Secret Manager or wrong project ID.

**Solution**:
1. Verify secrets exist: `gcloud secrets list --project=pyne-de-assignemet`
2. Create secrets via Terraform: `terraform apply -var-file="secrets.tfvars"`

### Error: Permission denied accessing secret

**Symptom**: GitHub Actions fails to access secrets despite authentication succeeding.

**Cause**: Service account lacks `secretmanager.secretAccessor` role.

**Solution**: Grant Secret Manager access via Terraform (should be automatic) or manually:

```bash
gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Error: Credentials file not found locally

**Symptom**: Local pipeline fails with "Service account key file not found".

**Cause**: `.env` file has wrong path to service account key.

**Solution**:
1. Verify key file exists: `ls keys/pyne-de-assignemet-dlt-sa-key.json`
2. Update `.env` with correct relative path from project root
3. Ensure path is relative, not absolute (for portability)

---

## 7. Quick Reference Commands

### View Secret Manager Secrets

```bash
# List all secrets
gcloud secrets list --project=pyne-de-assignemet

# View secret metadata (not content)
gcloud secrets describe dlt-service-account-key --project=pyne-de-assignemet

# Access secret value (requires secretAccessor role)
gcloud secrets versions access latest --secret="dlt-service-account-key" --project=pyne-de-assignemet
```

### Check IAM Bindings

```bash
# Check service account IAM policy
gcloud iam service-accounts get-iam-policy \
  github-actions@pyne-de-assignemet.iam.gserviceaccount.com \
  --project=pyne-de-assignemet

# Check project IAM policy for a service account
gcloud projects get-iam-policy pyne-de-assignemet \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:github-actions@pyne-de-assignemet.iam.gserviceaccount.com"
```

### Verify Workload Identity Federation

```bash
# List Workload Identity pools
gcloud iam workload-identity-pools list --location=global --project=pyne-de-assignemet

# List providers in a pool
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=github-actions-pool \
  --location=global \
  --project=pyne-de-assignemet

# Describe a provider
gcloud iam workload-identity-pools providers describe github-actions-provider \
  --workload-identity-pool=github-actions-pool \
  --location=global \
  --project=pyne-de-assignemet
```

---

## 8. Related Files

- `.github/workflows/pr-validation.yml` - GitHub Actions workflow using WIF authentication
- `infrastructure/main.tf` - Root Terraform configuration
- `infrastructure/modules/secret-manager/` - Secret Manager Terraform module
- `infrastructure/secrets.tfvars` - Secret values for Terraform (gitignored)
- `pipelines/dlt-ingestion/src/config.py` - Configuration loader for dlt pipeline
- `.env` - Local environment variables (gitignored)
- `.env.example` - Template for local environment variables
