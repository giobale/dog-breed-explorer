# Cloud Run Deployment

## Overview

The dlt pipeline runs as a **Cloud Run Job** triggered by **Cloud Scheduler**. The deployment workflow follows a build-once-deploy-everywhere pattern managed through CI/CD (GitHub Actions) and Infrastructure as Code (Terraform).

---

## Architecture

```
Container Image (Artifact Registry)
         ↓
   Cloud Run Job
         ↓
   Cloud Scheduler (cron trigger)
```

**Key Components:**
- **Cloud Run Job**: Serverless execution environment for containerized pipeline
- **Cloud Scheduler**: Automated job triggering on defined schedule
- **Artifact Registry**: Container image storage
- **Service Account**: Identity for runtime authentication

---

## Deployment Workflow

### 1. Image Build

**Location**: `pipelines/dlt-ingestion/Dockerfile`

Multi-stage build optimized for production:

```dockerfile
# Stage 1: Install dependencies
FROM python:3.11-slim AS builder
# Install system packages + Python dependencies

# Stage 2: Runtime image
FROM python:3.11-slim
# Copy only compiled packages and application code
```

**Build command**:
```bash
docker build -t <region>-docker.pkg.dev/<project>/<repository>/<image>:<tag> \
  pipelines/dlt-ingestion/
```

### 2. Image Push

Push to Artifact Registry:
```bash
docker push <region>-docker.pkg.dev/<project>/<repository>/<image>:<tag>
```

**Image naming convention**:
- Development: `<image>:pr-<number>`
- Production: `<image>:latest` and `<image>:<commit-sha>`

### 3. Infrastructure Deployment

**Terraform Module**: `infrastructure/modules/dlt-ingestion/`

Deploys:
- Cloud Run Job with container reference
- Cloud Scheduler for automated triggers
- IAM bindings for secret access

**Deployment command**:
```bash
cd infrastructure/
terraform init
terraform plan -var-file="secrets.tfvars"
terraform apply -var-file="secrets.tfvars"
```

**Required variables** (`secrets.tfvars`):
```hcl
dlt_service_account_email = "terraform-deploy@<project>.iam.gserviceaccount.com"
dlt_container_image       = "<region>-docker.pkg.dev/<project>/<repository>/<image>:<tag>"
```

### 4. Job Execution

**Manual trigger**:
```bash
gcloud run jobs execute dlt-dog-breeds-ingestion \
  --region=europe-west1 \
  --project=<project-id>
```

**Automated trigger**: Cloud Scheduler invokes job via HTTP POST to Cloud Run API endpoint.

---

## Authentication

### Service Account

**Identity**: `terraform-deploy@<project>.iam.gserviceaccount.com`

**Dual role**:
1. **Deployment**: Used by Terraform to provision infrastructure
2. **Runtime**: Attached to Cloud Run Job for pipeline execution

### How Authentication Works

**Key concept**: Application Default Credentials (ADC) is an authentication **mechanism**, not a separate identity. When ADC activates in Cloud Run, it uses the **attached service account** as its identity source.

**Configuration** (`infrastructure/modules/dlt-ingestion/main.tf:27`):
```terraform
service_account = var.service_account_email
```

**Runtime flow**:
```
Cloud Run Job starts with attached service account
       ↓
ADC automatically fetches credentials for that service account from metadata server
       ↓
Pipeline code calls Google APIs (BigQuery, Secret Manager, etc.)
       ↓
Google client libraries use ADC credentials (compute engine credentials type)
       ↓
All API calls authenticate AS terraform-deploy@<project>.iam.gserviceaccount.com
```

**What ADC provides**:
- Automatic credential discovery - no explicit authentication code needed
- Credentials for the attached service account identity
- Compute engine credential type (not service account key credentials)

**Important**: No `GOOGLE_APPLICATION_CREDENTIALS` environment variable is set or needed in Cloud Run. The service account identity comes from the job configuration, not from a JSON key file.

### dlt BigQuery Configuration

**Critical fix** (`pipeline.py:59-62`):
```python
destination=dlt.destinations.bigquery(
    location="US",
    project_id=config.bigquery_project_id  # Required for Cloud Run ADC
)
```

**Why explicit project_id is required**:
- ADC provides compute engine credentials (type: `google.auth.compute_engine.credentials.Credentials`)
- dlt expects either service account key credentials OR explicit project context
- Without `project_id`, dlt cannot parse compute engine credentials and fails with `InvalidGoogleNativeCredentialsType`
- Adding `project_id` tells dlt which project to use with the ADC-provided credentials

### Required IAM Roles

Service account needs:
- `roles/bigquery.dataEditor` - Write data to BigQuery
- `roles/bigquery.jobUser` - Execute BigQuery jobs
- `roles/secretmanager.secretAccessor` - Read secrets from Secret Manager
- `roles/run.invoker` - Allow Cloud Scheduler to trigger job

### Configuration Approach

**Current implementation**: Environment variables are hardcoded in Terraform configuration (`infrastructure/modules/dlt-ingestion/main.tf:33-56`) and passed directly to the container at runtime.

**Environment variables**:
```bash
GCP_PROJECT_ID=<project-id>
BIGQUERY_DATASET=dog_breeds_raw
DOG_API_BASE_URL=https://api.thedogapi.com/v1
DOG_API_ENDPOINT=breeds
ENVIRONMENT=production
```

**Secret Manager setup**: IAM bindings exist (`main.tf:82-101`) granting the service account access to secrets, but the pipeline currently doesn't pull values from Secret Manager - it reads from environment variables instead.

**What uses ADC credentials**:
- **BigQuery writes**: ADC authenticates as the service account to write data
- **Secret Manager** (if enabled): Would use ADC to read secrets, currently unused

---

## Scheduler Configuration

**Module**: `infrastructure/modules/dlt-ingestion/main.tf:76-98`

**Components**:
- **Schedule**: Cron format (configurable via `dlt_schedule` variable)
- **Time Zone**: Configurable (default: UTC)
- **Target**: Cloud Run Jobs API endpoint
- **Authentication**: OAuth token with service account identity

**Trigger mechanism**:
```
Cloud Scheduler → HTTP POST →
  https://<region>-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/<project>/jobs/<job-name>:run
```

---

## Resource Configuration

**Defined in**: `infrastructure/modules/dlt-ingestion/variables.tf`

**Defaults**:
- CPU: 1 vCPU
- Memory: 512Mi
- Timeout: 1800s (30 minutes)
- Max Retries: 1

**Customization**: Override in `secrets.tfvars` or module call.

---

## CI/CD Integration

### PR Validation Workflow

**File**: `.github/workflows/pr-validation.yml`

**Does NOT build/deploy container** - tests code only with:
- GitHub Actions service account (Workload Identity)
- Secrets from Secret Manager
- Temporary PR-specific BigQuery dataset

### Production Deployment Workflow

**Note**: Current setup appears to use manual Terraform deployment. A production workflow would typically:

1. Build container image on merge to main
2. Tag with commit SHA and `:latest`
3. Push to Artifact Registry
4. Update Terraform variable with new image
5. Run `terraform apply` to update Cloud Run Job

---

## Troubleshooting

### Authentication Errors

**Symptom**: `InvalidGoogleNativeCredentialsType` or credential parsing errors

**Solution**: Ensure `project_id` is explicitly passed to BigQuery destination (already fixed in `pipeline.py:61`)

### Job Timeout

**Symptom**: Job killed before completion

**Solution**: Increase `job_timeout` in Terraform variables (default: 1800s)

### Scheduler Not Triggering

**Check**:
```bash
gcloud scheduler jobs describe dlt-dog-breeds-weekly-trigger \
  --location=europe-west1 \
  --project=<project-id>
```

**Verify**: Service account has `roles/run.invoker` on Cloud Run Job

---

## Monitoring

**Cloud Run Job logs**:
```bash
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=dlt-dog-breeds-ingestion" \
  --project=<project-id> \
  --limit=50
```

**Scheduler execution history**:
```bash
gcloud scheduler jobs describe dlt-dog-breeds-weekly-trigger \
  --location=europe-west1 \
  --project=<project-id>
```
