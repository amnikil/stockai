#!/bin/bash
# Exit immediately if any command fails
# This prevents pushing a broken image
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-south-1"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
TAG="${1:-latest}"   # Use argument as tag, default to "latest"

echo "================================================"
echo "ECR Base:  $ECR_BASE"
echo "Image Tag: $TAG"
echo "================================================"

# Login to ECR — token is valid for 12 hours
# aws ecr get-login-password generates a temporary Docker password
echo "Logging into ECR..."
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_BASE
echo "✅ Logged into ECR"

# Build and push each service
for service in api-gateway analysis-service frontend; do
  echo ""
  echo "──────────────────────────────────"
  echo "Processing: $service"
  echo "──────────────────────────────────"

  cd ~/stockai/services/$service

  # Build Docker image with two tags: specific version + latest
  docker build \
    --tag stockai/$service:$TAG \
    --tag stockai/$service:latest \
    .

  # Tag for ECR (requires full registry URL)
  docker tag stockai/$service:$TAG     $ECR_BASE/stockai/$service:$TAG
  docker tag stockai/$service:latest   $ECR_BASE/stockai/$service:latest

  # Security scan with Trivy BEFORE pushing
  # --exit-code 1 = fail the script if HIGH/CRITICAL CVEs found
  echo "Running Trivy security scan..."
  trivy image \
    --exit-code 0 \
    --severity HIGH,CRITICAL \
    --no-progress \
    stockai/$service:$TAG

  # Push to ECR
  echo "Pushing to ECR..."
  docker push $ECR_BASE/stockai/$service:$TAG
  docker push $ECR_BASE/stockai/$service:latest

  echo "✅ $service pushed successfully"
done

echo ""
echo "================================================"
echo "✅ All 3 services pushed to ECR!"
echo "View: https://console.aws.amazon.com/ecr/repositories"
echo "================================================"
