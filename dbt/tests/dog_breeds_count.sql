{{ config(
    tags=['breeds']
) }}

WITH validation AS (
  SELECT COUNT(*) AS row_count
  FROM {{ ref('dim_breeds') }}
)
SELECT *
FROM validation
WHERE row_count = 0