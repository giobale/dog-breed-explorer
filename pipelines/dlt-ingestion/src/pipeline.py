# ABOUTME: Main entrypoint for dlt dog breeds pipeline orchestrating data extraction and loading.
# ABOUTME: Handles configuration loading, pipeline execution, error handling, and logging.

import sys
import os
# CICD trigger
# CRITICAL: Print immediately to verify container starts
print("=" * 80, file=sys.stderr, flush=True)
print("CONTAINER STARTING - Python script loaded", file=sys.stderr, flush=True)
print(f"Python version: {sys.version}", file=sys.stderr, flush=True)
print(f"Working directory: {os.getcwd()}", file=sys.stderr, flush=True)
print(f"GCP_PROJECT_ID: {os.getenv('GCP_PROJECT_ID')}", file=sys.stderr, flush=True)
print("=" * 80, file=sys.stderr, flush=True)

import logging
from typing import Dict, Any

import dlt

from config import PipelineConfig
from sources.api_source import dog_breeds_source

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stderr)],  # Use stderr for Cloud Run
)

logger = logging.getLogger(__name__)


def run_pipeline() -> Dict[str, Any]:
    """
    Execute the dog breeds data pipeline.

    Returns:
        Dictionary containing pipeline execution results and metrics.
    """
    try:
        logger.info("Starting dog breeds data pipeline")

        config = PipelineConfig.from_environment()
        logger.info(f"Configuration loaded: dataset={config.bigquery_dataset}, project={config.bigquery_project_id}")

        logger.info(f"Fetching data from: {config.full_api_url}")

        # Configure BigQuery credentials
        # In Cloud Run: Uses the service account attached to the job via ADC
        # Locally: Uses gcloud auth application-default login or GOOGLE_APPLICATION_CREDENTIALS
        logger.info("Creating pipeline with Application Default Credentials (ADC)")

        # When running on Cloud Run with ADC, dlt needs explicit project_id
        # This allows dlt to work with compute engine credentials
        pipeline = dlt.pipeline(
            pipeline_name="dog_breeds_pipeline",
            destination=dlt.destinations.bigquery(
                location="US",  # BigQuery location
                project_id=config.bigquery_project_id  # Required for Cloud Run ADC
            ),
            dataset_name=config.bigquery_dataset,
        )

        logger.info(f"Pipeline created - will use ADC from environment")
        logger.info(f"Pipeline will create dataset '{config.bigquery_dataset}' if it doesn't exist")

        #returns the dog_breeds_resource generator.
        source = dog_breeds_source(api_url=config.full_api_url) 

        logger.info("Running dlt pipeline")
        #executes the whole ETL for that source
        load_info = pipeline.run(source)

        logger.info("Pipeline execution completed successfully")
        logger.info(f"Load info: {load_info}")

        return {
            "status": "success",
            "load_info": str(load_info),
            "dataset": config.bigquery_dataset,
        }

    except Exception as e:
        logger.error(f"Pipeline execution failed: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    try:
        result = run_pipeline()
        logger.info(f"Pipeline result: {result}")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Pipeline failed with error: {e}")
        sys.exit(1)
