"""Sync Lambda: fetches OLX listings, applies criteria, stores results.

Triggered by EventBridge every 30 minutes. See docs/architecture.md, section 5.
"""

import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    logger.info("Sync started")
    # TODO: read config from SSM, fetch candidates via the source adapter,
    # upsert listings in DynamoDB, mark expired, write last_success_at.
    return {"status": "ok"}
