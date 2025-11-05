# ABOUTME: Main entrypoint for dlt dog breeds pipeline orchestrating data extraction and loading.
# ABOUTME: Handles configuration loading, pipeline execution, error handling, and logging.

import logging
import sys
from typing import Dict, Any

import dlt

from config import PipelineConfig
from sources.api_source import dog_breeds_source

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)

logger = logging.getLogger(__name__)


def run_pipeline() -> Dict[str, Any]:
    """
    Execute the dog breeds data pipeline.

    Returns:
        Dictionary containing pipeline execution results and metrics.

    Raises:
        Exception: If pipeline execution fails.
    """
    try:
        logger.info("Starting dog breeds data pipeline")

        config = PipelineConfig.from_environment()
        logger.info(f"Configuration loaded: dataset={config.bigquery_dataset}, project={config.bigquery_project_id}")

        logger.info(f"Fetching data from: {config.full_api_url}")

        pipeline = dlt.pipeline(
            pipeline_name="dog_breeds_pipeline",
            destination="bigquery",
            dataset_name=config.bigquery_dataset,
        )

        logger.info(f"Pipeline will create dataset '{config.bigquery_dataset}' if it doesn't exist")

        source = dog_breeds_source(api_url=config.full_api_url)

        logger.info("Running dlt pipeline")
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
