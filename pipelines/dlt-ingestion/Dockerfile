# ABOUTME: Multi-stage Dockerfile for dlt dog breeds pipeline optimized for production deployment.
# ABOUTME: Uses Python 3.11 slim base, installs dependencies, and configures runtime environment.

# Multi-stage build pattern for smaller final image

#The final image only contains:
#   - Python 3.11 runtime
#   - Your application code
#   - Compiled Python packages (no source build tools)

# Build stage: Install dependencies
FROM python:3.11-slim AS builder

WORKDIR /app

# Install system dependencies required for building Python packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Runtime stage: Minimal image with installed dependencies
FROM python:3.11-slim

WORKDIR /app

# Copy Python packages from builder stage
COPY --from=builder /root/.local /root/.local

# Add user site-packages to PATH
ENV PATH=/root/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

# Copy application source code
COPY src/ ./src/

# dlt will create .dlt directory automatically when pipeline runs
# No need to pre-create it

# Set Python path to include src directory
ENV PYTHONPATH=/app/src:$PYTHONPATH

# Change working directory to src where pipeline.py is located
# This ensures dlt looks for .dlt config in the correct location
WORKDIR /app/src

# Use direct Python execution - simpler and more reliable for Cloud Run
# -u flag ensures unbuffered output for Cloud Logging
ENTRYPOINT ["python", "-u"]
CMD ["pipeline.py"]

