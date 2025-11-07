# ABOUTME: Main documentation overview for the dog breeds analytics dbt project
# ABOUTME: Provides comprehensive guide to data models, architecture, and usage

{% docs __overview__ %}

# Dog Breeds Analytics dbt Project

## Overview

This dbt project transforms raw dog breed data from the Dog API into analytics-ready tables following a medallion architecture (bronze → silver → gold). The pipeline parses JSON data, normalizes life span information, and creates a denormalized analytics table for comprehensive breed analysis.

## Architecture

### Data Flow

```
Raw Data (Bronze)
    ↓
dog_breeds_raw.dog_breeds_resource (source)
    ↓
Silver Layer (Intermediate Views)
    ├── int_dog_breeds_parsed
    └── int_dog_breeds_normalized
    ↓
Gold Layer (Analytics Table)
    └── dim_breeds
```

### Layer Descriptions

**Bronze Layer (Raw)**
- Dataset: `dog_breeds_raw`
- Contains raw JSON data from dlt ingestion pipelines
- Minimal transformations, preserves source data integrity

**Silver Layer (Intermediate)**
- Dataset: `dog_breeds_silver`
- Materialized as **views** for cost efficiency
- Parses JSON and normalizes data types
- Extracts life span metrics from string fields

**Gold Layer (Analytics)**
- Dataset: `dog_breeds_gold`
- Materialized as **table** for query performance
- Denormalized breed information table
- Optimized for analytical queries and BI tools

## Key Models

### int_dog_breeds_parsed
Extracts essential fields from the raw JSON breed_json column into structured columns. Parses breed identifiers, names, temperament, life span, and weight data.

### int_dog_breeds_normalized
Extracts maximum life span in years from the life_span string field using regex pattern matching. Handles various life span formats to provide consistent numeric values.

### dim_breeds
**Analytics table** containing comprehensive breed information:
- Breed identifiers and names
- Temperament characteristics
- Weight ranges in kilograms
- Maximum life span in years
- All metrics in a single denormalized table for easy analysis

## Data Quality & Testing

The project implements comprehensive data quality checks:

- **Source tests**: Verify raw data integrity and freshness
- **Column tests**: NOT NULL, UNIQUE constraints
- **Freshness checks**: Alert if source data is stale

Tests run automatically on every dbt execution.

## Usage

### Running the Project

```bash
# Run all models
dbt run

# Run only silver layer
dbt run --select silver

# Run only gold layer
dbt run --select gold

# Run tests
dbt test

# Generate documentation
dbt docs generate
dbt docs serve
```

### Example Queries

**Get all breed information:**
```sql
SELECT
    breed_name,
    temperament,
    weight_class_kg,
    life_span_max_years
FROM dog_breeds_gold.dim_breeds
ORDER BY life_span_max_years DESC;
```

**Calculate average life span:**
```sql
SELECT
    AVG(life_span_max_years) AS avg_life_span,
    COUNT(*) AS total_breeds
FROM dog_breeds_gold.dim_breeds;
```

**Find breeds with specific characteristics:**
```sql
SELECT
    breed_name,
    temperament,
    life_span_max_years
FROM dog_breeds_gold.dim_breeds
WHERE temperament LIKE '%Friendly%'
ORDER BY breed_name;
```

## Timestamps

All models include two key timestamps:

- **ingested_at**: When the raw data was ingested (from source `updated_at`)
- **dbt_run_at**: When the dbt transformation was executed

These enable audit trails and data lineage tracking.

## Materialization Strategy

- **Silver models**: Views (no storage cost, always fresh)
- **Gold model**: Table (fast queries, scheduled refresh)

This balances cost efficiency with query performance.

{% enddocs %}
