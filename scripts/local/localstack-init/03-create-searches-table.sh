#!/bin/bash
# Creates the Searches table from docs/llstingApi.md (empty).
# Runs inside the LocalStack container once it is ready.
set -euo pipefail

TABLE=Searches

if awslocal dynamodb describe-table --table-name "$TABLE" > /dev/null 2>&1; then
  echo "Table $TABLE already exists"
  exit 0
fi

awslocal dynamodb create-table   --table-name "$TABLE"   --billing-mode PAY_PER_REQUEST   --attribute-definitions     AttributeName=id,AttributeType=S     AttributeName=userId,AttributeType=S     AttributeName=status,AttributeType=S     AttributeName=createdAt,AttributeType=S   --key-schema AttributeName=id,KeyType=HASH   --global-secondary-indexes '[{
    "IndexName": "userId-createdAt-index",
    "KeySchema": [
      {"AttributeName": "userId", "KeyType": "HASH"},
      {"AttributeName": "createdAt", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }, {
    "IndexName": "status-createdAt-index",
    "KeySchema": [
      {"AttributeName": "status", "KeyType": "HASH"},
      {"AttributeName": "createdAt", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]' > /dev/null

awslocal dynamodb wait table-exists --table-name "$TABLE"

echo "Created table $TABLE"
