# ABOUTME: Input variables for dlt-ingestion module configuration.
# ABOUTME: Defines Cloud Run Job and Scheduler parameters for the dlt pipeline.

variable "project_id" {
  description = "GCP project ID where Cloud Run Job will be created"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run Job deployment"
  type        = string
  default     = "europe-west1"
}

variable "service_account_email" {
  description = "Service account email for Cloud Run Job execution"
  type        = string
}

variable "container_image" {
  description = "Full container image URL in Artifact Registry"
  type        = string
}

variable "job_name" {
  description = "Name of the Cloud Run Job"
  type        = string
  default     = "dlt-dog-breeds-ingestion"
}

variable "scheduler_name" {
  description = "Name of the Cloud Scheduler job"
  type        = string
  default     = "dlt-dog-breeds-weekly-trigger"
}

variable "schedule" {
  description = "Cron schedule for Cloud Scheduler (default: every Monday at 9 AM UTC)"
  type        = string
  default     = "0 9 * * 1"
}

variable "time_zone" {
  description = "Time zone for Cloud Scheduler"
  type        = string
  default     = "UTC"
}

variable "job_timeout" {
  description = "Maximum execution time for the Cloud Run Job in seconds"
  type        = string
  default     = "1800"
}

variable "memory" {
  description = "Memory allocation for the Cloud Run Job container"
  type        = string
  default     = "512Mi"
}

variable "cpu" {
  description = "CPU allocation for the Cloud Run Job container"
  type        = string
  default     = "1"
}
