# ABOUTME: Configuration module for dlt pipeline loading environment variables and settings.
# ABOUTME: Provides configuration dataclass for API endpoints and BigQuery dataset settings.

import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

logger = logging.getLogger(__name__)


@dataclass
class PipelineConfig:
    """Configuration for the dog breeds data pipeline."""

    api_base_url: str
    api_endpoint: str
    bigquery_dataset: str
    bigquery_project_id: Optional[str] = None

    @classmethod
    def from_environment(cls, env_file_path: Optional[str] = None) -> "PipelineConfig":
        """
        Load configuration from environment variables.

        Args:
            env_file_path: Optional path to .env file. If not provided, searches from project root.

        Returns:
            PipelineConfig: Configuration object populated from environment.
        """
        try:
            # Calculate project root: src/config.py -> src -> dlt-ingestion -> pipelines -> dog-breed-explorer
            project_root = Path(__file__).resolve().parent.parent.parent.parent
            logger.info(f"Calculated project root: {project_root}")

            if env_file_path:
                dotenv_path = Path(env_file_path)
            else:
                dotenv_path = project_root / ".env"

            logger.info(f"Looking for .env at: {dotenv_path}")
            logger.info(f".env exists: {dotenv_path.exists()}")

            if dotenv_path.exists():
                load_dotenv(dotenv_path=dotenv_path)
                logger.info(f"Loaded .env from: {dotenv_path}")
            else:
                # .env file not found - check if running in containerized environment
                # In Docker, environment variables are passed directly via --env-file
                if os.getenv("GCP_PROJECT_ID"):
                    logger.info("No .env file found, but GCP_PROJECT_ID env var is set (likely running in container)")
                else:
                    raise FileNotFoundError(
                        f".env file not found at: {dotenv_path}. "
                        f"Project root: {project_root}"
                    )

            credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
            if credentials_path:
                logger.info(f"Found GOOGLE_APPLICATION_CREDENTIALS: {credentials_path}")
                if not Path(credentials_path).is_absolute():
                    abs_credentials_path = (project_root / credentials_path).resolve()
                    logger.info(f"Converting to absolute path: {abs_credentials_path}")
                    if abs_credentials_path.exists():
                        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(abs_credentials_path)
                        logger.info(f"Set GOOGLE_APPLICATION_CREDENTIALS to: {abs_credentials_path}")
                    else:
                        raise FileNotFoundError(
                            f"Service account key file not found at: {abs_credentials_path}. "
                            f"Please check GOOGLE_APPLICATION_CREDENTIALS in .env file. "
                            f"Project root: {project_root}"
                        )

            api_base_url = os.getenv("DOG_API_BASE_URL", "https://api.thedogapi.com/v1")
            api_endpoint = os.getenv("DOG_API_ENDPOINT", "breeds")
            bigquery_dataset = os.getenv("BIGQUERY_DATASET", "dog_breeds_raw")
            bigquery_project_id = os.getenv("GCP_PROJECT_ID")

            return cls(
                api_base_url=api_base_url,
                api_endpoint=api_endpoint,
                bigquery_dataset=bigquery_dataset,
                bigquery_project_id=bigquery_project_id,
            )
        except Exception as e:
            raise ValueError(f"Failed to load configuration: {e}")

    @property
    def full_api_url(self) -> str:
        """Construct the full API URL."""
        return f"{self.api_base_url}/{self.api_endpoint}"
