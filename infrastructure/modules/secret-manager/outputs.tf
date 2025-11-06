# ABOUTME: Output values from Secret Manager module for use in other modules.
# ABOUTME: Exports secret IDs and resource names for reference.

output "dlt_service_account_key_secret_id" {
  description = "ID of the DLT service account key secret"
  value       = google_secret_manager_secret.dlt_service_account_key.secret_id
}

output "dog_api_base_url_secret_id" {
  description = "ID of the Dog API base URL secret"
  value       = google_secret_manager_secret.dog_api_base_url.secret_id
}

output "dog_api_endpoint_secret_id" {
  description = "ID of the Dog API endpoint secret"
  value       = google_secret_manager_secret.dog_api_endpoint.secret_id
}

output "secret_names" {
  description = "Map of all created secret names"
  value = {
    service_account_key = google_secret_manager_secret.dlt_service_account_key.secret_id
    api_base_url        = google_secret_manager_secret.dog_api_base_url.secret_id
    api_endpoint        = google_secret_manager_secret.dog_api_endpoint.secret_id
  }
}
