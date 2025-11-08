# Dog Breeds Analytics - dbt Project

## Overview

This dbt project transforms raw dog breed data from the Dog API into analytics-ready tables. It implements a medallion architecture (raw (bronze) -> silver -> gold), comprehensive data quality testing, and documentation.

## Project Structure

```
dbt/
├── models/
│   ├── raw/                          # Source definitions for raw data     
│   ├── silver/                       # Intermediate models (views)
│   └── gold/                         # Analytics model (table)
├── macros/
├── docs/                             # Dbt project documentation
├── tests/                            # Custom data tests
├── dbt_project.yml                   # Project configuration
├── packages.yml                      # dbt package dependencies
└── requirements.txt                  # Python dependencies
```

## Prerequisites

2. **Profile Configuration**: Ensure `~/.dbt/profiles.yml` contains:
   ```yaml
   pyne-assignement-bigquery-db:
     target: dev
     outputs:
       dev:
         type: bigquery
         method: service-account
         keyfile: /path/to/your-service-account-key.json
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
```

### 5. Run Tests

```bash
# Run all tests
dbt test
```

### 6. Generate Documentation

```bash
dbt docs generate
dbt docs serve
```

Opens interactive documentation in your browser with data lineage DAG.


## Timestamps

All models include:
- **ingested_at**: When raw data was loaded (from `updated_at`)
- **dbt_run_at**: When dbt transformation executed

Use these for audit trails and incremental processing.

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

### Package Installation Errors
- If you see errors about missing `dbt_project.yml` in packages or corrupted package directories
- Clean and reinstall packages: `rm -rf dbt_packages/ && dbt deps`
- Run it whenever you update `packages.yml` or encounter package errors


## Performance Optimization

- **Silver models**: Views (no storage cost, always fresh data)
- **Gold model**: Table (fast query performance)
- **Denormalized design**: No joins required for common queries
- **Partitioning**: Consider partitioning by date for large datasets

