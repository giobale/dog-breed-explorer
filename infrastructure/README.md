# Infrastructure as Code (Terraform)

## Related Documentation

- [Secrets and Authentication](../docs/SECRETS_AND_AUTHENTICATION.md) - Detailed guide on secret management and Workload Identity
- [Cloud Run Deployment](../docs/CLOUD_RUN_DEPLOYMENT.md) - Cloud Run Job deployment architecture and troubleshooting
- [DLT Pipeline README](../pipelines/dlt-ingestion/README.md) - Application-level pipeline documentation

## Overview

This directory contains Terraform configurations that provision and manage the entire Google Cloud Platform infrastructure for the dog-breed-explorer data platform.

## Prerequisites

- Terraform >= 1.0
- Google Cloud SDK (`gcloud`) installed and configured
- GCP project with billing enabled
- Service account with Terraform deployment permissions
- Service account JSON key file in project root

### Required GCP APIs

The following APIs must be enabled in your GCP project:

```bash
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  secretmanager.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  artifactregistry.googleapis.com \
  --project=<your-project-id>
```

**Note**: The BigQuery API is not listed here as BigQuery datasets are managed through the BigQuery UI, not Terraform. However, the BigQuery API should be enabled for the dlt pipeline to function.

## Architecture

The infrastructure is organized into two Terraform modules:

1. **Secret Manager Module** - Stores credentials and environment variables
2. **DLT Ingestion Module** - Deploys Cloud Run Jobs with Cloud Scheduler triggers

```
infrastructure/
├── Root Layer (main.tf, variables.tf, backend.tf)
│   │
│   ├── Module: secret-manager  # Creates secrets and IAM bindings
│   │
│   └── Module: dlt-ingestion   # Deploys Cloud Run Jobs and Scheduler
```

**Note**: BigQuery datasets (`dog_breeds_raw`, `dog_breeds_staging`, `dog_breeds_marts`) are managed through the BigQuery UI, not Terraform.

## Setup

### 1. Configure Service Account

Ensure you have a service account JSON key file in the project root directory:

```bash
# Verify the key file exists
ls ../pyne-de-assignemet-tf-service-account-key.json
```

The service account should have these roles for Terraform deployment:
- `roles/run.admin` - Manage Cloud Run jobs
- `roles/cloudscheduler.admin` - Manage Cloud Scheduler jobs
- `roles/secretmanager.admin` - Manage Secret Manager secrets
- `roles/iam.serviceAccountUser` - Act as service accounts

**Note**: The service account also needs `roles/bigquery.admin` and `roles/artifactregistry.writer` for dlt pipeline execution and CI/CD, but these are not used by Terraform itself.

### 2. Configure Backend

Create the GCS bucket for Terraform state (one-time setup):

```bash
gsutil mb -p <your-project-id> -l europe-west1 gs://<your-project-id>-tf-state
gsutil versioning set on gs://<your-project-id>-tf-state
```

Update `backend.tf` with your bucket name:

```hcl
backend "gcs" {
  bucket = "<your-project-id>-tf-state"
  prefix = "terraform/state"
}
```

### 3. Configure Variables

Create `secrets.tfvars` from the example template:

```bash
cp secrets.tfvars.example secrets.tfvars
```

Edit `secrets.tfvars` with your values (all variables are configured here):

```hcl
# GCP Project Configuration
project_id = "your-gcp-project-id"
region     = "europe-west1"

# Service Account Configuration
service_account_key_path             = "../pyne-de-assignemet-tf-service-account-key.json"
github_actions_service_account_email = "github-actions@your-project.iam.gserviceaccount.com"
dlt_service_account_email            = "terraform-deploy@your-project.iam.gserviceaccount.com"

# DLT Pipeline Configuration - Always use :latest tag
dlt_container_image = "europe-west1-docker.pkg.dev/your-project/docker-repo/dlt-dog-breeds-pipeline:latest"
dlt_schedule        = "0 9 * * 1"  # Every Monday at 9 AM UTC

# Dog API Configuration
dog_api_base_url = "https://api.thedogapi.com/v1"
dog_api_endpoint = "breeds"
```

**Note**: The `terraform.tfvars` file is empty as all configuration is managed through `secrets.tfvars`.

### 4. Authenticate Terraform

Authenticate using Application Default Credentials:

```bash
gcloud auth application-default login
```

## Deployment

### Initialize Terraform

Initialize the backend and download providers:

```bash
cd infrastructure
terraform init
```

### Plan Changes

Preview the infrastructure changes:

```bash
terraform plan -var-file="secrets.tfvars" -var="project_id=pyne-de-assignemet"
```

### Apply Configuration

Deploy the infrastructure:

```bash
terraform apply -var-file="secrets.tfvars" -var="project_id=pyne-de-assignemet"
```

Type `yes` when prompted to confirm the changes.

### Verify Deployment

Check that resources were created:

```bash
# List secrets
gcloud secrets list --project=<your-project-id>

# List Cloud Run jobs
gcloud run jobs list --region=europe-west1 --project=<your-project-id>

# List Cloud Scheduler jobs
gcloud scheduler jobs list --location=europe-west1 --project=<your-project-id>
```

## Testing

### Prerequisites for Testing

Before testing the deployed infrastructure, ensure the following requirements are met:

1. **Container Image Pushed to Artifact Registry**

   The image must be built and pushed before deployment:

   ```bash
   # Build the image
   cd ../pipelines/dlt-ingestion
   docker build -t europe-west1-docker.pkg.dev/<your-project-id>/docker-repo/dlt-dog-breeds-pipeline:latest .

   # Authenticate Docker to Artifact Registry
   gcloud auth configure-docker europe-west1-docker.pkg.dev

   # Push the image
   docker push europe-west1-docker.pkg.dev/<your-project-id>/docker-repo/dlt-dog-breeds-pipeline:latest

   # Verify the image exists
   gcloud artifacts docker images list \
     europe-west1-docker.pkg.dev/<your-project-id>/docker-repo \
     --include-tags \
     --filter="package=dlt-dog-breeds-pipeline"
   ```

2. **Service Account Has Necessary Permissions**
   ```bash
   # Verify IAM roles
   gcloud projects get-iam-policy <your-project-id> \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:terraform-deploy@<your-project-id>.iam.gserviceaccount.com"
   ```

3. **Infrastructure Successfully Deployed**
   ```bash
   # Verify Cloud Run Job exists
   gcloud run jobs describe dlt-dog-breeds-ingestion \
     --region=europe-west1 \
     --project=<your-project-id>
   ```

### Test Cloud Run Job Manually

Trigger the dlt pipeline job manually:

```bash
gcloud run jobs execute dlt-dog-breeds-ingestion \
  --region=europe-west1 \
  --project=<your-project-id>
```

View job execution logs:

```bash
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=dlt-dog-breeds-ingestion" \
  --project=<your-project-id> \
  --limit=50 \
  --format=json
```

### Test Cloud Scheduler

Force the scheduler to trigger immediately:

```bash
gcloud scheduler jobs run dlt-dog-breeds-weekly-trigger \
  --location=europe-west1 \
  --project=<your-project-id>
```

### Verify Secret Manager Access

Test that the service account can access secrets:

```bash
# Impersonate the service account
gcloud secrets versions access latest \
  --secret="dlt-service-account-key" \
  --project=<your-project-id> \
  --impersonate-service-account=terraform-deploy@<your-project-id>.iam.gserviceaccount.com
```

## Project Structure

```
infrastructure/
├── main.tf                         # Root orchestration and module calls
├── variables.tf                    # Root-level variable definitions
├── outputs.tf                      # Root-level outputs (job name, scheduler name)
├── backend.tf                      # Remote state configuration (GCS bucket)
├── versions.tf                     # Terraform and provider version constraints
├── terraform.tfvars                # Empty - all variables in secrets.tfvars
├── secrets.tfvars                  # Sensitive variable values (gitignored)
├── secrets.tfvars.example          # Template for secrets.tfvars
├── modules/
│   ├── secret-manager/
│   │   ├── main.tf                 # Secret Manager resources and IAM bindings
│   │   ├── variables.tf            # Module input variables
│   │   └── outputs.tf              # Secret IDs and resource names
│   └── dlt-ingestion/
│       ├── main.tf                 # Cloud Run Job and Scheduler resources
│       ├── variables.tf            # Module input variables
│       └── outputs.tf              # Job and scheduler resource names
└── README.md                       # This file
```

## Modules

### Secret Manager Module

**Location**: `modules/secret-manager/`

**Purpose**: Creates and manages secrets in Google Cloud Secret Manager with appropriate IAM bindings.

**Resources Created**:
- `google_secret_manager_secret.dlt_service_account_key` - Service account JSON key
- `google_secret_manager_secret.dog_api_base_url` - Dog API base URL
- `google_secret_manager_secret.dog_api_endpoint` - Dog API endpoint path
- IAM bindings for GitHub Actions service account access

**Key Features**:
- Automatic replication across regions
- Service account impersonation for GitHub Actions (Workload Identity)
- IAM bindings for GitHub Actions service account (Artifact Registry, Secret Manager access)

**See Also**: [Secrets and Authentication Documentation](../docs/SECRETS_AND_AUTHENTICATION.md)

### DLT Ingestion Module

**Location**: `modules/dlt-ingestion/`

**Purpose**: Deploys Cloud Run Job for dlt pipeline execution with scheduled triggers.

**Resources Created**:
- `google_cloud_run_v2_job.dlt_ingestion` - Containerized dlt pipeline job
- `google_cloud_scheduler_job.dlt_trigger` - Weekly cron trigger
- IAM bindings for Secret Manager access

**Key Features**:
- Serverless execution with auto-scaling
- Configurable resource limits (CPU, memory, timeout)
- Environment variable injection from Terraform
- Service account authentication with ADC
- Scheduled execution via Cloud Scheduler

**Configuration Variables**:
- `container_image` - Full path to container image in Artifact Registry
- `schedule` - Cron expression (default: `0 9 * * 1` - Monday 9 AM UTC)
- `cpu` - CPU allocation (default: `1`)
- `memory` - Memory allocation (default: `512Mi`)
- `job_timeout` - Max execution time in seconds (default: `1800`)

**See Also**: [Cloud Run Deployment Documentation](../docs/CLOUD_RUN_DEPLOYMENT.md)

## State Management

### Remote State

Terraform state is stored remotely in a GCS bucket configured in `backend.tf`:

```hcl
backend "gcs" {
  bucket = "<your-project-id>-tf-state"
  prefix = "terraform/state"
}
```

**Benefits**:
- State locking prevents concurrent modifications
- State versioning enables rollback
- Team collaboration with shared state
- State encryption at rest

### Viewing State

List resources in state:

```bash
terraform state list
```

Show specific resource details:

```bash
terraform state show module.secret_manager.google_secret_manager_secret.dlt_service_account_key
```

### State Operations

Import existing resources:

```bash
terraform import module.dlt_ingestion.google_cloud_run_v2_job.dlt_ingestion projects/<project-id>/locations/europe-west1/jobs/dlt-dog-breeds-ingestion
```

## Updating Infrastructure

### Update Container Image

The container image always uses the `:latest` tag. To update the deployed image:

```bash
# 1. Build and push new image with :latest tag
cd ../pipelines/dlt-ingestion
docker build -t europe-west1-docker.pkg.dev/your-project/docker-repo/dlt-dog-breeds-pipeline:latest .
docker push europe-west1-docker.pkg.dev/your-project/docker-repo/dlt-dog-breeds-pipeline:latest

# 2. Force Cloud Run Job to use the new image
cd ../../infrastructure
terraform apply -var-file="secrets.tfvars" -replace="module.dlt_ingestion.google_cloud_run_v2_job.dlt_ingestion"
```

**Note**: The `-replace` flag forces Terraform to recreate the Cloud Run Job, pulling the latest image from Artifact Registry.

### Update Schedule

Modify the cron schedule:

```bash
# Edit secrets.tfvars
dlt_schedule = "0 6 * * *"  # Daily at 6 AM UTC

# Apply changes
terraform apply -var-file="secrets.tfvars"
```

### Update Secrets

Rotate service account keys or update API credentials:

```bash
# Update the JSON key file
cp new-service-account-key.json ../pyne-de-assignemet-tf-service-account-key.json

# Apply changes (only updates secret version, not the secret itself)
terraform apply -var-file="secrets.tfvars"
```

## Destroying Resources

### Destroy All Resources

**Warning**: This will delete all infrastructure managed by Terraform.

```bash
terraform destroy -var-file="secrets.tfvars"
```

### Destroy Specific Module

Destroy only the dlt-ingestion module:

```bash
terraform destroy -target=module.dlt_ingestion -var-file="secrets.tfvars"
```

## Troubleshooting

### "Error acquiring state lock"

**Symptom**: Terraform fails with lock acquisition error.

**Cause**: Another Terraform process is running or a previous run was interrupted.

**Solution**: Force unlock (use with caution):

```bash
terraform force-unlock <lock-id>
```

### "Error creating Secret: googleapi: Error 409: Secret already exists"

**Symptom**: Secret Manager resources fail to create.

**Cause**: Secrets already exist from previous deployment.

**Solution**: Import existing secrets into state:

```bash
terraform import module.secret_manager.google_secret_manager_secret.dlt_service_account_key projects/<project-id>/secrets/dlt-service-account-key
```

### "Error: Backend configuration changed"

**Symptom**: Terraform detects backend configuration changes.

**Cause**: Backend settings in `backend.tf` were modified.

**Solution**: Reinitialize backend:

```bash
terraform init -reconfigure
```

### "Error: Permission denied on service account"

**Symptom**: Terraform fails to create resources due to permission errors.

**Cause**: Service account lacks required IAM roles.

**Solution**: Grant necessary roles for Terraform deployment:

```bash
gcloud projects add-iam-policy-binding <project-id> \
  --member="serviceAccount:terraform-deploy@<project-id>.iam.gserviceaccount.com" \
  --role="roles/run.admin"
```

### Module output not available

**Symptom**: `terraform output` shows empty values.

**Cause**: Outputs defined in modules aren't exposed at root level.

**Solution**: Add module outputs to root `outputs.tf`:

```hcl
output "secret_ids" {
  value = module.secret_manager.secret_ids
}
```

## Best Practices

### Security
- Never commit `secrets.tfvars` or `*.tfstate` files to version control
- Use separate service accounts for Terraform and runtime workloads
- Enable Secret Manager audit logging
- Rotate service account keys regularly
- Use least-privilege IAM roles

### Deployment
- Always run `terraform plan` before `apply`
- Use `-var-file` for environment-specific configurations
- Tag resources with environment, owner, and purpose
- Implement CI/CD for Terraform deployments in production
