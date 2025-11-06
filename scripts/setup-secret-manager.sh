#!/bin/bash
# ABOUTME: Script to create and populate secrets in Google Secret Manager for CI/CD pipelines.
# ABOUTME: Stores service account keys and environment variables securely in GCP Secret Manager.

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Secret Manager Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Load .env file
if [ ! -f "${ENV_FILE}" ]; then
    echo -e "${RED}ERROR: .env file not found at ${ENV_FILE}${NC}"
    exit 1
fi

source "${ENV_FILE}"

# Validate required variables
if [ -z "${GCP_PROJECT_ID}" ]; then
    echo -e "${RED}ERROR: GCP_PROJECT_ID not set in .env${NC}"
    exit 1
fi

if [ -z "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
    echo -e "${RED}ERROR: GOOGLE_APPLICATION_CREDENTIALS not set in .env${NC}"
    exit 1
fi

# Resolve service account path
if [[ "${GOOGLE_APPLICATION_CREDENTIALS}" = /* ]]; then
    CREDS_FILE="${GOOGLE_APPLICATION_CREDENTIALS}"
else
    CREDS_FILE="${PROJECT_ROOT}/${GOOGLE_APPLICATION_CREDENTIALS}"
fi

if [ ! -f "${CREDS_FILE}" ]; then
    echo -e "${RED}ERROR: Service account key file not found at ${CREDS_FILE}${NC}"
    exit 1
fi

echo -e "${YELLOW}Using GCP Project: ${GCP_PROJECT_ID}${NC}"
echo -e "${YELLOW}Using credentials: ${CREDS_FILE}${NC}\n"

# Enable Secret Manager API
echo -e "${BLUE}Step 1: Enabling Secret Manager API...${NC}"
gcloud services enable secretmanager.googleapis.com --project="${GCP_PROJECT_ID}" || {
    echo -e "${YELLOW}Secret Manager API might already be enabled${NC}"
}
echo -e "${GREEN}✓ Secret Manager API enabled${NC}\n"

# Create secrets
echo -e "${BLUE}Step 2: Creating secrets in Secret Manager...${NC}\n"

# 1. Service Account Key
echo -e "${YELLOW}Creating secret: dlt-service-account-key${NC}"
if gcloud secrets describe dlt-service-account-key --project="${GCP_PROJECT_ID}" &>/dev/null; then
    echo -e "${YELLOW}Secret already exists, creating new version...${NC}"
    gcloud secrets versions add dlt-service-account-key \
        --data-file="${CREDS_FILE}" \
        --project="${GCP_PROJECT_ID}"
else
    gcloud secrets create dlt-service-account-key \
        --data-file="${CREDS_FILE}" \
        --replication-policy="automatic" \
        --project="${GCP_PROJECT_ID}"
fi
echo -e "${GREEN}✓ Service account key stored${NC}\n"

# 2. Dog API Base URL
echo -e "${YELLOW}Creating secret: dog-api-base-url${NC}"
DOG_API_BASE_URL=${DOG_API_BASE_URL:-https://api.thedogapi.com/v1}
if gcloud secrets describe dog-api-base-url --project="${GCP_PROJECT_ID}" &>/dev/null; then
    echo -e "${YELLOW}Secret already exists, creating new version...${NC}"
    echo -n "${DOG_API_BASE_URL}" | gcloud secrets versions add dog-api-base-url \
        --data-file=- \
        --project="${GCP_PROJECT_ID}"
else
    echo -n "${DOG_API_BASE_URL}" | gcloud secrets create dog-api-base-url \
        --data-file=- \
        --replication-policy="automatic" \
        --project="${GCP_PROJECT_ID}"
fi
echo -e "${GREEN}✓ Dog API base URL stored${NC}\n"

# 3. Dog API Endpoint
echo -e "${YELLOW}Creating secret: dog-api-endpoint${NC}"
DOG_API_ENDPOINT=${DOG_API_ENDPOINT:-breeds}
if gcloud secrets describe dog-api-endpoint --project="${GCP_PROJECT_ID}" &>/dev/null; then
    echo -e "${YELLOW}Secret already exists, creating new version...${NC}"
    echo -n "${DOG_API_ENDPOINT}" | gcloud secrets versions add dog-api-endpoint \
        --data-file=- \
        --project="${GCP_PROJECT_ID}"
else
    echo -n "${DOG_API_ENDPOINT}" | gcloud secrets create dog-api-endpoint \
        --data-file=- \
        --replication-policy="automatic" \
        --project="${GCP_PROJECT_ID}"
fi
echo -e "${GREEN}✓ Dog API endpoint stored${NC}\n"

# Setup Workload Identity for GitHub Actions
echo -e "${BLUE}Step 3: Setting up Workload Identity for GitHub Actions...${NC}\n"

read -p "Do you want to set up Workload Identity Federation for GitHub Actions? (y/n): " setup_wif
if [[ "$setup_wif" =~ ^[Yy]$ ]]; then
    read -p "Enter your GitHub repository (format: owner/repo): " GITHUB_REPO

    if [ -z "${GITHUB_REPO}" ]; then
        echo -e "${RED}ERROR: GitHub repository not provided${NC}"
        exit 1
    fi

    # Enable IAM API
    gcloud services enable iam.googleapis.com --project="${GCP_PROJECT_ID}"
    gcloud services enable iamcredentials.googleapis.com --project="${GCP_PROJECT_ID}"
    gcloud services enable sts.googleapis.com --project="${GCP_PROJECT_ID}"

    # Create Workload Identity Pool
    POOL_NAME="github-actions-pool"
    echo -e "${YELLOW}Creating Workload Identity Pool: ${POOL_NAME}${NC}"

    if ! gcloud iam workload-identity-pools describe "${POOL_NAME}" \
        --location="global" \
        --project="${GCP_PROJECT_ID}" &>/dev/null; then

        gcloud iam workload-identity-pools create "${POOL_NAME}" \
            --location="global" \
            --display-name="GitHub Actions Pool" \
            --project="${GCP_PROJECT_ID}"
    else
        echo -e "${YELLOW}Pool already exists${NC}"
    fi

    # Create Workload Identity Provider
    PROVIDER_NAME="github-provider"
    echo -e "${YELLOW}Creating Workload Identity Provider: ${PROVIDER_NAME}${NC}"

    if ! gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
        --workload-identity-pool="${POOL_NAME}" \
        --location="global" \
        --project="${GCP_PROJECT_ID}" &>/dev/null; then

        gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
            --workload-identity-pool="${POOL_NAME}" \
            --location="global" \
            --issuer-uri="https://token.actions.githubusercontent.com" \
            --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
            --attribute-condition="assertion.repository=='${GITHUB_REPO}'" \
            --project="${GCP_PROJECT_ID}"
    else
        echo -e "${YELLOW}Provider already exists${NC}"
    fi

    # Create service account for GitHub Actions
    SA_NAME="github-actions-sa"
    SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

    echo -e "${YELLOW}Creating service account: ${SA_EMAIL}${NC}"

    if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT_ID}" &>/dev/null; then
        gcloud iam service-accounts create "${SA_NAME}" \
            --display-name="GitHub Actions Service Account" \
            --project="${GCP_PROJECT_ID}"
    else
        echo -e "${YELLOW}Service account already exists${NC}"
    fi

    # Grant necessary permissions
    echo -e "${YELLOW}Granting IAM permissions...${NC}"

    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/bigquery.dataEditor" \
        --condition=None

    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/bigquery.jobUser" \
        --condition=None

    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/secretmanager.secretAccessor" \
        --condition=None

    # Allow GitHub Actions to impersonate service account
    echo -e "${YELLOW}Configuring Workload Identity binding...${NC}"

    gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe ${GCP_PROJECT_ID} --format='value(projectNumber)')/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GITHUB_REPO}" \
        --project="${GCP_PROJECT_ID}"

    # Get Workload Identity Provider resource name
    WIF_PROVIDER=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
        --workload-identity-pool="${POOL_NAME}" \
        --location="global" \
        --project="${GCP_PROJECT_ID}" \
        --format="value(name)")

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Workload Identity setup complete!${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    echo -e "${BLUE}Add these secrets to your GitHub repository:${NC}"
    echo -e "${YELLOW}Repository Settings > Secrets and variables > Actions${NC}\n"
    echo -e "GCP_PROJECT_ID:"
    echo -e "  ${GCP_PROJECT_ID}\n"
    echo -e "GCP_WORKLOAD_IDENTITY_PROVIDER:"
    echo -e "  ${WIF_PROVIDER}\n"
    echo -e "GCP_SERVICE_ACCOUNT:"
    echo -e "  ${SA_EMAIL}\n"
else
    echo -e "${YELLOW}Skipping Workload Identity setup${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Secret Manager setup complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Created secrets:${NC}"
echo -e "  - dlt-service-account-key"
echo -e "  - dog-api-base-url"
echo -e "  - dog-api-endpoint\n"
