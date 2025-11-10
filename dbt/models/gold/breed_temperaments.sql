{{
  config(
    materialized='table',
    tags=['gold']
  )
}}

SELECT DISTINCT
  breed_id,
  TRIM(trait) AS temperament
FROM {{ ref('int_dog_breeds_normalized') }}
CROSS JOIN UNNEST(SPLIT(temperament, ',')) AS trait
WHERE temperament IS NOT NULL
ORDER BY breed_id, temperament