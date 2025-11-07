-- ABOUTME: Normalizes weight data from string ranges to numeric min/max values
-- ABOUTME: Handles parsing of weight ranges in both imperial and metric units

{{
  config(
    materialized='view',
    tags=['silver', 'intermediate', 'normalizing']
  )
}}

WITH parsed_breeds AS (
    SELECT * FROM {{ ref('int_dog_breeds_parsed') }}
),

weight_normalized AS (
    SELECT
        row_id,
        _dlt_id,
        _dlt_load_id,
        breed_id,
        breed_name,
        temperament,
        life_span,
        weight_class_kg,
        CAST(
                (
                SELECT IF(
                    ARRAY_LENGTH(REGEXP_EXTRACT_ALL(life_span, r'\d+')) > 1,
                    REGEXP_EXTRACT_ALL(life_span, r'\d+')[OFFSET(1)],
                    REGEXP_EXTRACT_ALL(life_span, r'\d+')[OFFSET(0)]
                )
                ) AS INT64
            ) AS life_span_max_years,
        ingested_at,
        dbt_run_at

    FROM parsed_breeds
)

SELECT
    row_id,
    _dlt_id,
    _dlt_load_id,
    breed_id,
    breed_name,
    temperament,
    life_span,
    weight_class_kg,
    life_span_max_years,
    ingested_at,
    dbt_run_at
FROM weight_normalized
