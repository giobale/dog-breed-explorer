-- ABOUTME: Intermediate model that parses JSON from raw dog breeds source
-- ABOUTME: Extracts structured fields and handles NULL values for downstream consumption

{{
  config(
    materialized='view',
    tags=['silver', 'intermediate', 'json_parsing']
  )
}}

WITH source_data AS (
    SELECT
        row_id,
        breed_json,
        updated_at,
        _dlt_load_id,
        _dlt_id
    FROM {{ source('dog_breeds_raw', 'dog_breeds_resource') }}
),

parsed_breeds AS (
    SELECT
        row_id,
        _dlt_id,
        _dlt_load_id,
        CAST(JSON_EXTRACT_SCALAR(breed_json, '$.id') AS INT64) AS breed_id,
        JSON_EXTRACT_SCALAR(breed_json, '$.name') AS breed_name,
        JSON_EXTRACT_SCALAR(breed_json, '$.temperament') AS temperament,
        JSON_EXTRACT_SCALAR(breed_json, '$.life_span') AS life_span,
        JSON_EXTRACT_SCALAR(breed_json, '$.weight.metric') AS weight_kg,
        updated_at AS ingested_at,
        CURRENT_TIMESTAMP() AS dbt_run_at

    FROM source_data
)

SELECT
    row_id,
    _dlt_id,
    _dlt_load_id,
    breed_id,
    breed_name,
    temperament,
    life_span,
    weight_kg,
    ingested_at,
    dbt_run_at
FROM parsed_breeds
WHERE breed_id IS NOT NULL
