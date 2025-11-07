# Dog Breeds Analytics - dbt Project

## Overview

This dbt project transforms raw dog breed data from the Dog API into analytics-ready tables. It implements a medallion architecture (bronze -> silver -> gold) with a denormalized analytics table, comprehensive data quality testing, and documentation.

## Project Structure

```
dbt/
├── models/
│   ├── raw/
│   │   └── sources.yml              # Source definitions for raw data
│   ├── silver/                       # Intermediate models (views)
│   │   ├── int_dog_breeds_parsed.sql
│   │   ├── int_dog_breeds_normalized.sql
│   │   └── schema.yml
│   └── gold/                         # Analytics model (table)
│       ├── dim_breeds.sql
│       └── schema.yml
├── macros/
│   └── generate_schema_name.sql     # Custom schema naming logic
├── docs/
│   └── overview.md                   # Project documentation
├── tests/                            # Custom data tests
├── dbt_project.yml                   # Project configuration
├── packages.yml                      # dbt package dependencies
└── requirements.txt                  # Python dependencies
```

## Architecture

### Data Flow

1. **Bronze Layer** (Raw): `dog_breeds_raw.dog_breeds_resource`
   - Source data ingested via dlt pipelines
   - JSON format with minimal transformations

2. **Silver Layer** (Intermediate): Materialized as **views**
   - `int_dog_breeds_parsed`: Extracts JSON fields into columns
   - `int_dog_breeds_normalized`: Extracts maximum life span in years

3. **Gold Layer** (Analytics): Materialized as **table**
   - `dim_breeds`: Denormalized table with all breed information

### Data Model

The gold layer contains a single denormalized table:

```
┌──────────────────────────┐
│       dim_breeds         │
├──────────────────────────┤
│ breed_id (PK)            │
│ breed_name               │
│ temperament              │
│ weight_class_kg                │
│ life_span_max_years      │
└──────────────────────────┘
```

This structure provides:
- Simple querying without joins
- All breed information in one place
- Optimal performance for BI tools
- Easy to understand and maintain

## Prerequisites

1. **dbt**: Install dbt-bigquery
   ```bash
   pip install -r requirements.txt
   ```

2. **Profile Configuration**: Ensure `~/.dbt/profiles.yml` contains:
   ```yaml
   pyne-assignement-bigquery-db:
     target: dev
     outputs:
       dev:
         type: bigquery
         method: service-account
         keyfile: /path/to/pyne-de-assignemet-tf-service-account-key.json
         project: pyne-de-assignemet
         dataset: dog_breeds_raw
   ```

3. **BigQuery Datasets**: Ensure these datasets exist:
   - `dog_breeds_raw` (source data)
   - `dog_breeds_silver` (created automatically)
   - `dog_breeds_gold` (created automatically)

## Getting Started

### 1. Setup Virtual Environment

```bash
cd dbt

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # macOS/Linux
# Or: venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt
```

### 2. Install dbt Packages

```bash
dbt deps
```

### 3. Test Connection

```bash
dbt debug
```

Verifies connection to BigQuery and profile configuration.

### 4. Run Models

```bash
# Run all models
dbt run

# Run specific layer
dbt run --select silver
dbt run --select gold

# Run specific model with dependencies
dbt run --select +dim_breeds
```

### 5. Run Tests

```bash
# Run all tests
dbt test

# Test specific model
dbt test --select dim_breeds

# Test sources only
dbt test --select source:dog_breeds_raw
```

### 6. Generate Documentation

```bash
dbt docs generate
dbt docs serve
```

Opens interactive documentation in your browser with data lineage DAG.

## Key Model

### `dim_breeds`

**Purpose**: Comprehensive breed information table for analytics

**Columns**:
- `breed_id`: Unique identifier (Primary Key)
- `breed_name`: Breed name
- `temperament`: Personality traits
- `weight_class_kg`: Weight range in kilograms (string)
- `life_span_max_years`: Maximum life span in years (integer)

**Query Examples**:

**Get all breeds ordered by life span:**
```sql
SELECT
    breed_name,
    temperament,
    weight_class_kg,
    life_span_max_years
FROM dog_breeds_gold.dim_breeds
ORDER BY life_span_max_years DESC;
```

**Find breeds with specific traits:**
```sql
SELECT
    breed_name,
    temperament,
    life_span_max_years
FROM dog_breeds_gold.dim_breeds
WHERE temperament LIKE '%Friendly%'
ORDER BY breed_name;
```

**Calculate statistics:**
```sql
SELECT
    AVG(life_span_max_years) AS avg_life_span,
    MIN(life_span_max_years) AS min_life_span,
    MAX(life_span_max_years) AS max_life_span,
    COUNT(*) AS total_breeds
FROM dog_breeds_gold.dim_breeds;
```

## Data Quality

The project implements comprehensive testing:

### Source Tests
- Data freshness (warns if >10 days old)
- Row count validation
- Primary key uniqueness

### Model Tests
- NOT NULL constraints
- UNIQUE constraints
- Data type validation

### Test Execution

Tests run automatically with `dbt test`. Failed tests report errors in the terminal without creating additional datasets.

## Development Workflow

1. **Make Changes**: Edit SQL models in `models/` directory
2. **Test Locally**: Run `dbt run` and `dbt test`
3. **Review Changes**: Use `dbt docs generate` to visualize lineage
4. **Commit**: Push changes to Git
5. **CI/CD**: GitHub Actions runs tests automatically

## Common Commands

```bash
# Full refresh (rebuild all tables)
dbt run --full-refresh

# Run models with specific tag
dbt run --select tag:silver
dbt run --select tag:gold

# Compile SQL without running
dbt compile

# Clean build artifacts
dbt clean

# List all models
dbt ls

# Show model dependencies
dbt ls --select +dim_breeds --resource-type model
```

## Troubleshooting

### "Relation not found" Error
- Ensure source dataset `dog_breeds_raw` exists in BigQuery
- Verify table `dog_breeds_resource` has data
- Check service account has read permissions
- Run upstream models first: `dbt run --select +model_name`

### "Credentials" Error
- Verify service account key file path in `~/.dbt/profiles.yml`
- Ensure key file has correct permissions (600)
- Check service account has BigQuery Data Editor role

### Tests Failing
- Review test failure details in terminal output
- Check source data quality in raw tables
- Verify regex patterns for life span extraction

### Wrong Dataset Names
- The custom `generate_schema_name` macro ensures exact schema names
- Silver models go to `dog_breeds_silver` (not `dog_breeds_raw_dog_breeds_silver`)
- Gold model goes to `dog_breeds_gold`

## Timestamps

All models include:
- **ingested_at**: When raw data was loaded (from `updated_at`)
- **dbt_run_at**: When dbt transformation executed

Use these for audit trails and incremental processing.

## Performance Optimization

- **Silver models**: Views (no storage cost, always fresh data)
- **Gold model**: Table (fast query performance)
- **Denormalized design**: No joins required for common queries
- **Partitioning**: Consider partitioning by date for large datasets

## Contributing

1. Create feature branch
2. Add/modify models and tests
3. Run `dbt run` and `dbt test` locally
4. Update documentation
5. Submit pull request

## Support

For issues or questions:
- Review dbt documentation: https://docs.getdbt.com
- Check BigQuery logs for execution details
- Review compiled SQL in `target/compiled/` directory
