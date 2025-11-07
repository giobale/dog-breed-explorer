# ABOUTME: Terraform module for Google Secret Manager resources for CI/CD pipelines.
# ABOUTME: Creates secrets for service account keys, API credentials, and environment variables.

# Enable Secret Manager API
resource "google_project_service" "secretmanager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  disable_on_destroy = false
}

# Secret for DLT service account key (JSON file content)
resource "google_secret_manager_secret" "dlt_service_account_key" {
  project   = var.project_id
  secret_id = "dlt-service-account-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

# Secret version for service account key
# Note: The actual secret data must be provided via terraform.tfvars or CLI
resource "google_secret_manager_secret_version" "dlt_service_account_key" {
  secret = google_secret_manager_secret.dlt_service_account_key.id

  # Read from file path provided in variables
  secret_data = var.service_account_key_content

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Secret for Dog API base URL
resource "google_secret_manager_secret" "dog_api_base_url" {
  project   = var.project_id
  secret_id = "dog-api-base-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "dog_api_base_url" {
  secret      = google_secret_manager_secret.dog_api_base_url.id
  secret_data = var.dog_api_base_url
}

# Secret for Dog API endpoint
resource "google_secret_manager_secret" "dog_api_endpoint" {
  project   = var.project_id
  secret_id = "dog-api-endpoint"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "dog_api_endpoint" {
  secret      = google_secret_manager_secret.dog_api_endpoint.id
  secret_data = var.dog_api_endpoint
}

# IAM binding to allow service account to access secrets
resource "google_secret_manager_secret_iam_member" "dlt_service_account_key_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.dlt_service_account_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.github_actions_service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "dog_api_base_url_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.dog_api_base_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.github_actions_service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "dog_api_endpoint_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.dog_api_endpoint.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.github_actions_service_account_email}"
}

# Grant GitHub Actions service account permission to push Docker images to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "github_actions_writer" {
  project    = var.project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_repository
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.github_actions_service_account_email}"
}

# Grant GitHub Actions service account BigQuery permissions for dbt operations
# This role includes: jobs.create, datasets.get, tables.create/update/delete/getData
resource "google_project_iam_member" "github_actions_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${var.github_actions_service_account_email}"
}

# Grant GitHub Actions service account BigQuery User role for job creation
# This role includes: jobs.create, jobs.get, jobs.list
resource "google_project_iam_member" "github_actions_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${var.github_actions_service_account_email}"
}
