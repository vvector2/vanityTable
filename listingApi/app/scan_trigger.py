"""Starts the sync Lambda for a manual scan. See docs/llstingApi.md, section Scan jobs."""

import json
import logging
from typing import Any

from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)


class ScanTriggerFailed(Exception):
    pass


class ScanTrigger:
    """Invokes the sync Lambda asynchronously with the job id in the payload (`{"job_id": ...}`).

    Without a function name (local runs) nothing is invoked; the job waits until it times out
    or a local sync reports it (quickSync -JobId).
    """

    def __init__(self, lambda_client: Any, function_name: str | None) -> None:
        self._lambda = lambda_client
        self._function_name = function_name

    def request_scan(self, job_id: str) -> None:
        if not self._function_name:
            logger.warning("SCAN_FUNCTION_NAME not set, scan job %s was not sent to the sync job", job_id)
            return
        try:
            # "Event" queues the run and returns 202 at once; the run itself takes minutes.
            self._lambda.invoke(
                FunctionName=self._function_name,
                InvocationType="Event",
                Payload=json.dumps({"job_id": job_id}).encode("utf-8"),
            )
        except ClientError as error:
            raise ScanTriggerFailed(str(error)) from error
