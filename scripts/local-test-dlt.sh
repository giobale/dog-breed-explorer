#!/bin/bash
# ABOUTME: Script to test dlt pipeline locally using Docker with environment variables from .env file.
# ABOUTME: Validates prerequisites, builds image, runs pipeline container, and displays results.

set -e  # Exit on any error

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DLT_DIR="${PROJECT_ROOT}/pipelines/dlt-ingestion"
ENV_FILE="${PROJECT_ROOT}/.env"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DLT Pipeline Local Docker Test${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Validate prerequisites
echo -e "${YELLOW}Step 1: Validating prerequisites...${NC}"

if [ ! -f "${ENV_FILE}" ]; then
    echo -e "${RED}ERROR: .env file not found at ${ENV_FILE}${NC}"
    echo -e "${YELLOW}Please create a .env file from .env.example and configure your credentials.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ .env file found${NC}"

# Source .env to validate GOOGLE_APPLICATION_CREDENTIALS path
source "${ENV_FILE}"

if [ -z "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
    echo -e "${RED}ERROR: GOOGLE_APPLICATION_CREDENTIALS not set in .env file${NC}"
    exit 1
fi

# Handle both absolute and relative paths for GOOGLE_APPLICATION_CREDENTIALS
if [[ "${GOOGLE_APPLICATION_CREDENTIALS}" = /* ]]; then
    # Absolute path
    CREDS_FILE="${GOOGLE_APPLICATION_CREDENTIALS}"
else
    # Relative path - resolve from project root
    CREDS_FILE="${PROJECT_ROOT}/${GOOGLE_APPLICATION_CREDENTIALS}"
fi

if [ ! -f "${CREDS_FILE}" ]; then
    echo -e "${RED}ERROR: Service account key file not found at ${CREDS_FILE}${NC}"
    echo -e "${YELLOW}Please ensure the path in .env points to a valid service account JSON file.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Service account credentials found at: ${CREDS_FILE}${NC}"

# Export the absolute path for docker-compose
export GOOGLE_APPLICATION_CREDENTIALS="${CREDS_FILE}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker is not installed or not in PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is available${NC}\n"

# Build Docker image
echo -e "${YELLOW}Step 2: Building Docker image...${NC}"
cd "${DLT_DIR}"

docker build -t dlt-dog-breeds-pipeline:local . || {
    echo -e "${RED}ERROR: Docker build failed${NC}"
    exit 1
}
echo -e "${GREEN}✓ Docker image built successfully${NC}\n"

# Run pipeline using docker-compose
echo -e "${YELLOW}Step 3: Running dlt pipeline in Docker container...${NC}"
echo -e "${BLUE}Using environment variables from: ${ENV_FILE}${NC}"
echo -e "${BLUE}Using service account: ${CREDS_FILE}${NC}\n"

docker-compose up --build --abort-on-container-exit || {
    echo -e "${RED}ERROR: Pipeline execution failed${NC}"
    docker-compose down
    exit 1
}

# Cleanup
echo -e "\n${YELLOW}Step 4: Cleaning up containers...${NC}"
docker-compose down
echo -e "${GREEN}✓ Containers cleaned up${NC}\n"

# Success message
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ DLT Pipeline executed successfully!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Verify data in BigQuery using the GCP Console"
echo -e "2. Check dataset: ${BIGQUERY_DATASET:-dog_breeds_raw}"
echo -e "3. Check table: dog_breeds_resource\n"
