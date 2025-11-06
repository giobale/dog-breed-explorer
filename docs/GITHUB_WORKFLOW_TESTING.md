# GitHub Workflow Testing Guide

## Overview

This guide walks you through testing the PR validation workflow from scratch, including first-time setup with Secret Manager deployment and subsequent tests.

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] GCP project created with billing enabled
- [ ] `gcloud` CLI installed and authenticated
- [ ] Terraform installed (>= 1.0)
- [ ] GitHub repository with admin access
- [ ] Workload Identity Federation configured (see `SECRET_MANAGER_SETUP.md`)
- [ ] GitHub Secrets added to repository:
  - `GCP_PROJECT_ID`
  - `GCP_WORKLOAD_IDENTITY_PROVIDER`
  - `GCP_SERVICE_ACCOUNT`

---

## Part 1: First-Time Test (With Secret Manager Deployment)

### Step 1: Verify Workload Identity Federation

Check that Workload Identity Federation is configured correctly:

```bash
# List workload identity pools
gcloud iam workload-identity-pools list --location=global --project=YOUR_PROJECT_ID

# List providers in the pool
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=github-actions-pool \
  --location=global \
  --project=YOUR_PROJECT_ID
```

Expected output: You should see `github-actions-pool` and `github-actions-provider`.

### Step 2: Verify GitHub Secrets

Go to your GitHub repository:
```
Settings → Secrets and variables → Actions → Repository secrets
```

Verify these secrets exist:
- `GCP_PROJECT_ID`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`

### Step 3: Prepare Terraform Configuration

```bash
# Navigate to infrastructure directory
cd infrastructure

# Create secrets.tfvars from example
cp secrets.tfvars.example secrets.tfvars

# Edit secrets.tfvars with your values
nano secrets.tfvars
```

Example `secrets.tfvars`:
```hcl
service_account_key_path = "../keys/pyne-de-assignemet-dlt-sa-key.json"
dog_api_base_url = "https://api.thedogapi.com/v1"
dog_api_endpoint = "breeds"
github_actions_service_account_email = "github-actions@pyne-de-assignemet.iam.gserviceaccount.com"
```

**IMPORTANT**: Ensure the service account key file exists at the specified path.

### Step 4: Initialize Terraform Backend

Since you've configured the GCS backend, initialize Terraform:

```bash
# Still in infrastructure/ directory
terraform init

# If you have existing local state, it will ask to migrate
# Type 'yes' to copy state to GCS bucket
```

### Step 5: Deploy Secret Manager

```bash
# Review what will be created
terraform plan -var-file="secrets.tfvars" -var="project_id=pyne-de-assignemet"

# Deploy the secrets
terraform apply -var-file="secrets.tfvars" -var="project_id=pyne-de-assignemet"
```

Type `yes` when prompted.

### Step 6: Verify Secrets in GCP

```bash
# List secrets
gcloud secrets list --project=pyne-de-assignemet

# Check specific secret (shows metadata, not content)
gcloud secrets describe dlt-service-account-key --project=pyne-de-assignemet
gcloud secrets describe dog-api-base-url --project=pyne-de-assignemet
gcloud secrets describe dog-api-endpoint --project=pyne-de-assignemet
```

Expected output: Three secrets should be listed.

### Step 7: Create a Test Pull Request

```bash
# Make sure you're on your feature branch
git branch

# Make a small change to trigger the workflow
echo "# Test PR" >> pipelines/dlt-ingestion/README.md

# Commit and push
git add pipelines/dlt-ingestion/README.md
git commit -m "test: trigger PR validation workflow"
git push origin dlt_pipeline_fetch_api
```

### Step 8: Create Pull Request on GitHub

1. Go to your GitHub repository
2. Click "Pull requests" → "New pull request"
3. Base branch: `main` (or `master`)
4. Compare branch: `dlt_pipeline_fetch_api`
5. Click "Create pull request"
6. Add title: "Test: PR Validation Workflow"
7. Click "Create pull request"

### Step 9: Monitor Workflow Execution

1. Go to "Actions" tab in your GitHub repository
2. Click on the "PR Validation" workflow run
3. Click on "Test DLT Pipeline" job
4. Watch the steps execute in real-time

### Step 10: Verify Workflow Steps

The workflow should execute these steps:

1. **Checkout code** ✓
2. **Authenticate to Google Cloud** ✓
   - Should complete without errors
   - Indicates Workload Identity is working
3. **Set up Cloud SDK** ✓
4. **Retrieve secrets from Secret Manager** ✓
   - Should successfully fetch all three secrets
   - Check logs for: "Exported secret: DOG_API_BASE_URL"
5. **Set PR-specific dataset name** ✓
   - Should show: "Using BigQuery dataset: dog_breeds_raw_pr_XXX"
6. **Set up Python** ✓
7. **Install dependencies** ✓
8. **Run integration test with PR dataset** ✓ or ✗
   - This will create a BigQuery dataset and run the pipeline
9. **Cleanup PR dataset** ✓
   - Should run even if test fails (due to `if: always()`)

### Step 11: Verify BigQuery Dataset (If Test Passed)

If the test passed and dataset cleanup worked:

```bash
# List datasets to verify cleanup
bq ls --project_id=pyne-de-assignemet

# Should NOT see dog_breeds_raw_pr_XXX (cleanup worked)
# Should see dog_breeds_raw (if you ran pipeline locally before)
```

### Step 12: Check for Errors

If the workflow failed, common issues:

**Authentication Failed**
```
Error: google-github-actions/auth failed with: retry authorization error
```
→ Check Workload Identity Federation setup
→ Verify service account has `workloadIdentityUser` role

**Secret Access Denied**
```
Error: gcloud secrets versions access: Permission denied
```
→ Check that `github-actions` service account has `secretmanager.secretAccessor` role
→ Verify IAM bindings in Terraform output

**BigQuery Permission Denied**
```
Error: 403 Forbidden: BigQuery access denied
```
→ The service account in Secret Manager needs BigQuery permissions
→ Grant `roles/bigquery.dataEditor` and `roles/bigquery.jobUser` to dlt service account

---

## Part 2: Subsequent Tests (After Initial Setup)

Once Secret Manager is deployed, subsequent tests are much simpler.

### Quick Test: Trigger Workflow from Existing PR

If you already have a PR open:

```bash
# Make a trivial change
echo "# Update $(date)" >> pipelines/dlt-ingestion/README.md

# Commit and push
git add pipelines/dlt-ingestion/README.md
git commit -m "test: trigger workflow again"
git push origin dlt_pipeline_fetch_api
```

The workflow will trigger automatically on the push.

### Test: Update Secrets

If you need to change API URLs or credentials:

```bash
cd infrastructure

# Edit secrets.tfvars
nano secrets.tfvars

# Apply changes
terraform apply -var-file="secrets.tfvars" -var="project_id=pyne-de-assignemet"

# Trigger workflow again (push to PR branch)
```

### Test: Manual Workflow Trigger (Optional)

To enable manual workflow triggers, add this to `.github/workflows/pr-validation.yml`:

```yaml
on:
  pull_request:
    branches:
      - main
      - master
    paths:
      - 'pipelines/dlt-ingestion/**'
      - '.github/workflows/pr-validation.yml'
  workflow_dispatch:  # Add this line
```

Then you can manually trigger from GitHub UI:
1. Go to "Actions" tab
2. Select "PR Validation" workflow
3. Click "Run workflow"

---

## Troubleshooting Common Issues

### Issue: Workflow doesn't trigger

**Cause**: Changed files not in `paths` filter

**Solution**:
- PR validation only triggers for changes in `pipelines/dlt-ingestion/` or the workflow file itself
- Make sure your changes are in these directories

### Issue: Workload Identity authentication fails

**Error**:
```
Error: google-github-actions/auth failed with: failed to generate Google Cloud access token
```

**Debug Steps**:
```bash
# 1. Get your GitHub repository in owner/repo format
GITHUB_REPO="your-username/dog-breed-explorer"

# 2. Get your GCP project number (not ID)
gcloud projects describe pyne-de-assignemet --format="value(projectNumber)"

# 3. Verify service account binding
gcloud iam service-accounts get-iam-policy \
  github-actions@pyne-de-assignemet.iam.gserviceaccount.com \
  --project=pyne-de-assignemet

# Look for a binding with:
# - role: roles/iam.workloadIdentityUser
# - member containing your repository path
```

### Issue: Secret Manager access denied

**Error**:
```
ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED
```

**Solution**:
```bash
# Grant Secret Manager access to GitHub Actions service account
gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:github-actions@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Issue: BigQuery dataset creation fails

**Error**:
```
google.api_core.exceptions.Forbidden: 403 Access Denied
```

**Solution**: The dlt service account (stored in Secret Manager) needs BigQuery permissions:

```bash
# Get the dlt service account email from your key file
# Then grant permissions:
gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:dlt-pipeline@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding pyne-de-assignemet \
  --member="serviceAccount:dlt-pipeline@pyne-de-assignemet.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

### Issue: Python dependencies fail to install

**Error**:
```
ERROR: Could not find a version that satisfies the requirement
```

**Solution**: Check `pipelines/dlt-ingestion/requirements.txt` for version conflicts

---

## Verification Checklist

After a successful workflow run, verify:

- [ ] Workflow status is green (✓ passed)
- [ ] All steps completed successfully
- [ ] PR-specific dataset was created (check logs)
- [ ] PR-specific dataset was cleaned up (check `bq ls`)
- [ ] No error messages in workflow logs
- [ ] Secrets were retrieved successfully
- [ ] Integration test passed

---

## Clean Up Test Resources

After testing, you may want to clean up:

```bash
# Delete any leftover PR datasets
bq ls --project_id=pyne-de-assignemet | grep "dog_breeds_raw_pr_"
bq rm -r -f -d pyne-de-assignemet:dog_breeds_raw_pr_XXX

# Close the test PR (don't merge)
# Do this from GitHub UI
```

---

## Next Steps

Once the workflow is working:

1. **Merge the PR** to deploy to main branch
2. **Set up production deployment workflow** (if needed)
3. **Configure branch protection rules** to require PR validation before merge
4. **Document any environment-specific configurations**

---

## Related Documentation

- `SECRET_MANAGER_SETUP.md` - Complete Secret Manager and Workload Identity setup
- `.github/workflows/pr-validation.yml` - The actual workflow file
- `infrastructure/` - Terraform configuration for secrets
