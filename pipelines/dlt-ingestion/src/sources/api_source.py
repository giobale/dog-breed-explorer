# ABOUTME: Dog breeds API source for dlt pipeline fetching breed data from TheDogAPI.
# ABOUTME: Transforms raw API response into structured format with row_id, breed_json, and updated_at.

import logging
from datetime import datetime, timezone
from typing import Any, Dict, Iterator, List

import dlt
from dlt.common.schema.typing import TDataType
import requests

logger = logging.getLogger(__name__)

#dlt.resource decorator turns your plain Python function into a DLT resource—a loadable data stream with schema, load options, and lifecycle that the pipeline can manage.
#without the decorator it’s just a generator function; with @dlt.resource it becomes a first-class ETL unit that DLT can discover, type, batch, and load into BigQuery with the behavior you specified.
@dlt.source
def dog_breeds_source(api_url: str) -> Any:
    """
    DLT source for fetching dog breeds from TheDogAPI.

    Args:
        api_url: Full URL to the dog breeds API endpoint.

    Returns:
        DLT resource for dog breeds data.
    """
    return dog_breeds_resource(api_url)


@dlt.resource(
    write_disposition="replace",
    primary_key="row_id",
    columns={
        "row_id": {"data_type": "bigint"},
        "breed_json": {"data_type": "json"},
        "updated_at": {"data_type": "timestamp"},
    },
)
def dog_breeds_resource(api_url: str) -> Iterator[Dict[str, Any]]: #look that an iterator gets returned
    """
    Fetch dog breeds from API and transform to target schema.

    The resource fetches the complete API response array and yields each breed element
    as-is without any parsing or modification. Each breed JSON object is stored in its
    entirety in the breed_json column.

     -> write_disposition="replace" ensures that each pipeline run replaces all existing
    data in the table, guaranteeing the dataset always contains the latest API response.

    Args:
        api_url: Full URL to the dog breeds API endpoint.

    Yields:
        Dictionary with:
        - row_id: Sequential number generated during iteration (1, 2, 3, ...)
        - breed_json: Complete breed object from API response (no parsing)
        - updated_at: Timestamp when data was fetched

    Raises:
        requests.RequestException: If API request fails.
    """
    try:
        logger.info(f"Fetching dog breeds from: {api_url}")
        response = requests.get(api_url, timeout=30)
        response.raise_for_status()

        breeds_data: List[Dict[str, Any]] = response.json()
        logger.info(f"Successfully fetched {len(breeds_data)} dog breeds from API")

        timestamp = datetime.now(timezone.utc)
        logger.info(f"Pipeline will REPLACE existing data (write_disposition=replace)")
        #As soon as Python sees yield inside a function, calling that function returns an iterator (a generator object) instead of running everything at once.
        #Produces values one at a time. Each yield hands one value to the caller and pauses the function, keeping its local variables and execution state.
        #A return ends the function immediately. With yield, you can produce many values over time.
        for row_id, breed in enumerate(breeds_data, start=1):
            yield {
                "row_id": row_id,
                "breed_json": breed,
                "updated_at": timestamp,
            }
            if row_id == 1:
                logger.debug(f"Sample breed JSON keys: {list(breed.keys())}")

        logger.info(f"Prepared {len(breeds_data)} complete breed records for BigQuery")

    except requests.RequestException as e:
        logger.error(f"Failed to fetch dog breeds: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error while processing dog breeds: {e}")
        raise
