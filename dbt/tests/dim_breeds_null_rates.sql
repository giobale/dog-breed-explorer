{{
  config(
    tags=['gold']
  )
}}

WITH stats AS (
  SELECT
    COUNT(*) AS total_rows,
    COUNTIF(life_span_max_years IS NULL) AS null_life_span,
    COUNTIF(weight_class_kg IS NULL) AS null_weight_class
  FROM {{ ref('dim_breeds') }}
),
validation AS (
  SELECT
    SAFE_DIVIDE(null_life_span, total_rows) AS life_span_null_rate,
    SAFE_DIVIDE(null_weight_class, total_rows) AS weight_class_null_rate
  FROM stats
)
SELECT
  *
FROM validation
WHERE life_span_null_rate > 0.1
   OR weight_class_null_rate > 0.1
