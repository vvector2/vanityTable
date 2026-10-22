#!/bin/bash
# Creates the ScanJobs table from docs/llstingApi.md (empty).
# Runs inside the LocalStack container once it is ready.
set -euo pipefail

TABLE=ScanJobs

if awslocal dynamodb describe-table --table-name "$TABLE" > /dev/null 2>&1; then
  echo "Table $TABLE already exists"
  exit 0
fi

awslocal dynamodb create-table \
  --table-name "$TABLE" \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=kind,AttributeType=S \
    AttributeName=createdAt,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --global-secondary-indexes '[{
    "IndexName": "kind-createdAt-index",
    "KeySchema": [
      {"AttributeName": "kind", "KeyType": "HASH"},
      {"AttributeName": "createdAt", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]' > /dev/null

awslocal dynamodb wait table-exists --table-name "$TABLE"

echo "Created table $TABLE"
