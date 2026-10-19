#!/bin/bash
# Creates the Listings table from docs/llstingApi.md and seeds a few sample listings.
# Runs inside the LocalStack container once it is ready.
set -euo pipefail

TABLE=Listings

if awslocal dynamodb describe-table --table-name "$TABLE" > /dev/null 2>&1; then
  echo "Table $TABLE already exists"
  exit 0
fi

awslocal dynamodb create-table \
  --table-name "$TABLE" \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=status,AttributeType=S \
    AttributeName=firstSeenAt,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --global-secondary-indexes '[{
    "IndexName": "status-firstSeenAt-index",
    "KeySchema": [
      {"AttributeName": "status", "KeyType": "HASH"},
      {"AttributeName": "firstSeenAt", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]' > /dev/null

awslocal dynamodb wait table-exists --table-name "$TABLE"

seed() {
  awslocal dynamodb put-item --table-name "$TABLE" --item "$1" > /dev/null
}

seed '{"id": {"S": "local-1"}, "title": {"S": "Toaletka retro z lustrem, lata 60"}, "price": {"N": "450"}, "currency": {"S": "PLN"}, "location": {"S": "Kraków"}, "url": {"S": "https://www.olx.pl/"}, "images": {"L": [{"S": "https://picsum.photos/seed/toaletka1/800/600"}]}, "description": {"S": "Drewniana toaletka PRL, stan dobry."}, "status": {"S": "new"}, "firstSeenAt": {"S": "2026-10-18T08:00:00Z"}}'
seed '{"id": {"S": "local-2"}, "title": {"S": "Stara toaletka vintage"}, "price": {"N": "300"}, "currency": {"S": "PLN"}, "location": {"S": "Łódź"}, "url": {"S": "https://www.olx.pl/"}, "images": {"L": [{"S": "https://picsum.photos/seed/toaletka2/800/600"}]}, "status": {"S": "new"}, "firstSeenAt": {"S": "2026-10-18T09:30:00Z"}}'
seed '{"id": {"S": "local-3"}, "title": {"S": "Toaletka z szufladami"}, "price": {"N": "200"}, "currency": {"S": "PLN"}, "url": {"S": "https://www.olx.pl/"}, "images": {"L": [{"S": "https://picsum.photos/seed/toaletka3/800/600"}]}, "status": {"S": "saved"}, "firstSeenAt": {"S": "2026-10-17T12:00:00Z"}}'
seed '{"id": {"S": "local-4"}, "title": {"S": "Toaleta turystyczna"}, "currency": {"S": "PLN"}, "url": {"S": "https://www.olx.pl/"}, "images": {"L": []}, "status": {"S": "rejected"}, "firstSeenAt": {"S": "2026-10-16T12:00:00Z"}}'

echo "Created and seeded table $TABLE"
