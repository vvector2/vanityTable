# Listings table from docs/llstingApi.md, section DynamoDB.
resource "aws_dynamodb_table" "listings" {
  name         = "${var.name}-listings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  # Decisions cannot be rebuilt from OLX, so guard the table against accidental loss.
  deletion_protection_enabled = true

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "firstSeenAt"
    type = "S"
  }

  attribute {
    name = "sourceId"
    type = "S"
  }

  global_secondary_index {
    name            = "status-firstSeenAt-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "status"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "firstSeenAt"
      key_type       = "RANGE"
    }
  }

  # Lookup by sourceId (e.g. olx:123). A GSI cannot enforce uniqueness; sourceId is unique
  # because the API derives id as a UUIDv5 of it and creates with attribute_not_exists(id).
  global_secondary_index {
    name            = "sourceId-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "sourceId"
      key_type       = "HASH"
    }
  }
}

# One item per sync run (manual or scheduled), see docs/llstingApi.md, section Scan jobs.
# Short-lived status data, so no deletion protection or point-in-time recovery.
resource "aws_dynamodb_table" "scan_jobs" {
  name         = "${var.name}-scan-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "kind"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # The API sets expiresAt to 3 days after creation; DynamoDB deletes expired items for free.
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  # Every job has kind = "scan", so one query lists all jobs newest first.
  global_secondary_index {
    name            = "kind-createdAt-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "kind"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "createdAt"
      key_type       = "RANGE"
    }
  }
}
