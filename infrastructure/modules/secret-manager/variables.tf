# ABOUTME: Input variables for Secret Manager module configuration.
# ABOUTME: Defines secrets content, API endpoints, and IAM bindings.

variable "project_id" {
  description = "GCP project ID where secrets will be created"
  type        = string
}

variable "service_account_key_content" {
  description = "Content of the service account JSON key file (sensitive)"
  type        = string
  sensitive   = true
}

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

variable "github_actions_service_account_email" {
  description = "Service account email used by GitHub Actions for authentication"
  type        = string
}

variable "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  type        = string
  default     = "europe-west1"
}

variable "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "cicd-push-repository"
}
