{{
  config(
    materialized='table',
    tags=['gold']
  )
}}

WITH normalized_breeds AS (
    SELECT * FROM {{ ref('int_dog_breeds_normalized') }}
),
dim_breeds AS (
    SELECT
        breed_id,
        breed_name,
        breed_group,
        temperament,
        weight_class_kg,
        life_span_max_years
    FROM normalized_breeds
)
SELECT *
FROM dim_breeds

