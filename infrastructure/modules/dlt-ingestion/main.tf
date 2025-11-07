# ABOUTME: Terraform module for dlt pipeline Cloud Run Job and Cloud Scheduler.
# ABOUTME: Deploys containerized dlt pipeline with scheduled weekly execution.

# Enable required APIs
resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloud_scheduler" {
  project = var.project_id
  service = "cloudscheduler.googleapis.com"

  disable_on_destroy = false
}

# Cloud Run Job for dlt pipeline execution
resource "google_cloud_run_v2_job" "dlt_ingestion" {
  name     = var.job_name
  location = var.region
  project  = var.project_id

  template {
    template {
      service_account = var.service_account_email

      containers {
        image = var.container_image

        # Environment variables from Secret Manager
        env {
          name = "GCP_PROJECT_ID"
          value = var.project_id
        }

        env {
          name = "BIGQUERY_DATASET"
          value = "dog_breeds_raw"
        }

        env {
          name = "ENVIRONMENT"
          value = "production"
        }

        env {
          name = "DOG_API_BASE_URL"
          value = "https://api.thedogapi.com/v1"
        }

        env {
          name = "DOG_API_ENDPOINT"
          value = "breeds"
        }

        # Resource limits
        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }
      }

      # Job execution settings
      timeout         = "${var.job_timeout}s"
      max_retries     = 1
    }
  }

  depends_on = [google_project_service.cloud_run]
}

# Cloud Scheduler to trigger Cloud Run Job weekly
resource "google_cloud_scheduler_job" "dlt_trigger" {
  name        = var.scheduler_name
  description = "Triggers dlt dog breeds ingestion pipeline every Monday"
  schedule    = var.schedule
  time_zone   = var.time_zone
  region      = var.region
  project     = var.project_id

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${var.job_name}:run"

    oauth_token {
      service_account_email = var.service_account_email
    }
  }

  depends_on = [
    google_project_service.cloud_scheduler,
    google_cloud_run_v2_job.dlt_ingestion
  ]
}

# Grant service account permission to access secrets
resource "google_secret_manager_secret_iam_member" "dlt_service_account_key_accessor" {
  project   = var.project_id
  secret_id = "dlt-service-account-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "dog_api_base_url_accessor" {
  project   = var.project_id
  secret_id = "dog-api-base-url"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "dog_api_endpoint_accessor" {
  project   = var.project_id
  secret_id = "dog-api-endpoint"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}
