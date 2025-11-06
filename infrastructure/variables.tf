# ABOUTME: Root-level Terraform variables for infrastructure configuration.
# ABOUTME: Defines GCP project settings and service account configurations.

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

# Service Account for DLT pipeline
variable "service_account_key_path" {
  description = "Path to service account JSON key file"
  type        = string
  sensitive   = true
}

# Dog API configuration
variable "dog_api_base_url" {
  description = "Base URL for The Dog API"
  type        = string
  default     = "https://api.thedogapi.com/v1"
}

variable "dog_api_endpoint" {
  description = "API endpoint path for dog breeds"
  type        = string
  default     = "breeds"
}

# GitHub Actions service account
variable "github_actions_service_account_email" {
  description = "Service account email used by GitHub Actions"
  type        = string
}

# DLT service account (for Cloud Run jobs)
variable "dlt_service_account_email" {
  description = "Service account email for DLT Cloud Run jobs"
  type        = string
  default     = ""
}

# DLT container image (for Cloud Run jobs)
variable "dlt_container_image" {
  description = "Container image URL for DLT pipeline"
  type        = string
  default     = ""
}
