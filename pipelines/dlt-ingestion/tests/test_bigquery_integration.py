# ABOUTME: Integration test for BigQuery dataset and table creation using actual GCP credentials.
# ABOUTME: Tests end-to-end pipeline execution from API fetch to BigQuery insertion.

import os
import sys
from pathlib import Path

import pytest
from google.cloud import bigquery

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from config import PipelineConfig
from pipeline import run_pipeline


@pytest.fixture
def bigquery_client():
    """Create BigQuery client using credentials from .env file."""
    config = PipelineConfig.from_environment()

    if not config.bigquery_project_id:
        pytest.skip("GCP_PROJECT_ID not set in .env file")

    client = bigquery.Client(project=config.bigquery_project_id)
    return client


@pytest.fixture
def config():
    """Load pipeline configuration from .env file."""
    return PipelineConfig.from_environment()


def test_pipeline_creates_dataset_and_table_in_bigquery(bigquery_client, config):
    """
    Test that the pipeline creates the BigQuery dataset and table with correct schema.

    This integration test:
    1. Runs the complete dlt pipeline
    2. Verifies the dataset was created in BigQuery
    3. Verifies the table was created with correct schema
    4. Verifies data was loaded into the table
    """
    try:
        print("\n" + "=" * 80)
        print("INTEGRATION TEST: BigQuery Dataset and Table Creation")
        print("=" * 80)

        print(f"\nProject ID: {config.bigquery_project_id}")
        print(f"Dataset: {config.bigquery_dataset}")
        print(f"API URL: {config.full_api_url}")

        print("\n--- Step 1: Running dlt pipeline ---")
        result = run_pipeline()

        assert result["status"] == "success", "Pipeline execution should succeed"
        print(f"Pipeline Status: {result['status']}")

        print("\n--- Step 2: Verifying dataset exists in BigQuery ---")
        dataset_id = f"{config.bigquery_project_id}.{config.bigquery_dataset}"
        dataset = bigquery_client.get_dataset(dataset_id)

        assert dataset is not None, f"Dataset {dataset_id} should exist"
        print(f"✓ Dataset found: {dataset.dataset_id}")
        print(f"  Location: {dataset.location}")
        print(f"  Created: {dataset.created}")

        print("\n--- Step 3: Verifying table exists with correct schema ---")
        table_id = f"{dataset_id}.dog_breeds_resource"
        table = bigquery_client.get_table(table_id)

        assert table is not None, f"Table {table_id} should exist"
        print(f"✓ Table found: {table.table_id}")
        print(f"  Num rows: {table.num_rows}")

        print(f"\n  Schema:")
        expected_columns = {"row_id", "breed_json", "updated_at"}
        actual_columns = {field.name for field in table.schema}

        breed_json_field = None
        for field in table.schema:
            print(f"    - {field.name}: {field.field_type}")
            if field.name == "breed_json":
                breed_json_field = field

        assert expected_columns.issubset(actual_columns), \
            f"Table should contain columns {expected_columns}, found {actual_columns}"

        assert breed_json_field is not None, "breed_json column should exist"
        assert breed_json_field.field_type == "JSON", \
            f"breed_json column should be JSON type, but got {breed_json_field.field_type}"
        print(f"\n✓ Verified: breed_json column is JSON type")

        print("\n--- Step 4: Verifying data was loaded ---")
        query = f"""
        SELECT COUNT(*) as row_count
        FROM `{table_id}`
        """
        query_job = bigquery_client.query(query)
        results = list(query_job.result())
        row_count = results[0].row_count

        assert row_count > 0, "Table should contain data"
        print(f"✓ Table contains {row_count} rows")

        print("\n--- Step 5: Displaying sample data ---")
        query = f"""
        SELECT row_id, breed_json, updated_at
        FROM `{table_id}`
        LIMIT 3
        """
        query_job = bigquery_client.query(query)

        print("\nSample rows:")
        for idx, row in enumerate(query_job.result(), 1):
            print(f"\n  Row {idx}:")
            print(f"    row_id: {row.row_id}")
            print(f"    breed_json type: {type(row.breed_json)}")
            if isinstance(row.breed_json, dict):
                print(f"    breed_json (dict): name={row.breed_json.get('name')}, id={row.breed_json.get('id')}")
            else:
                print(f"    breed_json: {str(row.breed_json)[:100]}...")
            print(f"    updated_at: {row.updated_at}")

        print("\n" + "=" * 80)
        print("✓ ALL TESTS PASSED")
        print("=" * 80)

    except Exception as e:
        print(f"\n✗ TEST FAILED: {e}")
        raise
