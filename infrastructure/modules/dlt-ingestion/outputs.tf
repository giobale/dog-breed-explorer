# ABOUTME: Output values from dlt-ingestion module.
# ABOUTME: Exposes Cloud Run Job and Scheduler resource information.

output "cloud_run_job_name" {
  description = "Name of the Cloud Run Job"
  value       = google_cloud_run_v2_job.dlt_ingestion.name
}

output "cloud_run_job_id" {
  description = "Full ID of the Cloud Run Job"
  value       = google_cloud_run_v2_job.dlt_ingestion.id
}

output "cloud_scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.dlt_trigger.name
}

output "cloud_scheduler_job_id" {
  description = "Full ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.dlt_trigger.id
}

output "schedule" {
  description = "Cron schedule for the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.dlt_trigger.schedule
}

output "next_run_time" {
  description = "Next scheduled execution time"
  value       = "Every Monday at 9:00 AM UTC (${var.schedule})"
}
