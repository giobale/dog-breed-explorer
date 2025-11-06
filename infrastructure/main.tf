# ABOUTME: Root Terraform configuration orchestrating all infrastructure modules.
# ABOUTME: Provisions Secret Manager and dlt ingestion resources on GCP.

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Backend configuration for storing state in GCS
  backend "gcs" {
    bucket = "pyne-assignement-tf-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Local variables
locals {
  # Read service account key from file
  service_account_key_content = file(var.service_account_key_path)
}

# Secret Manager module - Stores credentials and environment variables
module "secret_manager" {
  source = "./modules/secret-manager"

  project_id                            = var.project_id
  service_account_key_content           = local.service_account_key_content
  dog_api_base_url                      = var.dog_api_base_url
  dog_api_endpoint                      = var.dog_api_endpoint
  github_actions_service_account_email  = var.github_actions_service_account_email
}

# DLT Ingestion module - Creates Cloud Run jobs for data ingestion
# Uncomment when ready to deploy
# module "dlt_ingestion" {
#   source = "./modules/dlt-ingestion"
#
#   project_id         = var.project_id
#   region             = var.region
#   service_account_email = var.dlt_service_account_email
#   container_image    = var.dlt_container_image
# }
