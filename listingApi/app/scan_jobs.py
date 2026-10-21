"""Scan jobs: one item per sync run, manual or scheduled. See docs/llstingApi.md, section Scan jobs.

The UI creates a job (`created`) with POST /scan-job; the API invokes the sync Lambda
asynchronously with the job id. The Lambda reports `running` and then `succeeded` or
`failed` through PUT /scan-job/{id}. Scheduled runs report the same way under their own id,
so they start at `running`.

A job still `created` or `running` after JOB_TIMEOUT is reported as `failed`: the Lambda timeout is
15 minutes, so such a run was killed before it could report. Items expire through
DynamoDB TTL (`expiresAt`) after RETENTION.
"""

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any

from boto3.dynamodb.conditions import Attr, Key

from app.models import ScanJobDto, ScanJobStatus

CREATED_INDEX = "kind-createdAt-index"
# Constant partition key of CREATED_INDEX, so all jobs can be read newest first.
KIND = "scan"
JOB_TIMEOUT = timedelta(minutes=15)
RETENTION = timedelta(days=3)
# Not finished yet: blocks a new manual scan until it ends or times out.
ACTIVE = (ScanJobStatus.CREATED, ScanJobStatus.RUNNING)
TIMED_OUT_ERROR = "No result within 15 minutes"


class ScanJobNotFound(Exception):
    pass


def _iso(moment: datetime) -> str:
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def to_dto(item: dict[str, Any], now: datetime) -> ScanJobDto:
    status = ScanJobStatus(item["status"])
    error = item.get("error")
    if status in ACTIVE and datetime.fromisoformat(item["createdAt"]) <= now - JOB_TIMEOUT:
        status, error = ScanJobStatus.FAILED, TIMED_OUT_ERROR
    return ScanJobDto(
        id=item["id"],
        status=status,
        created_at=item["createdAt"],
        finished_at=item.get("finishedAt"),
        error=error,
    )


class ScanJobRepository:
    def __init__(self, table: Any) -> None:
        self._table = table

    def _newest_first(self, **kwargs: Any) -> Iterator[dict[str, Any]]:
        paginator = self._table.meta.client.get_paginator("query")
        pages = paginator.paginate(
            TableName=self._table.name,
            IndexName=CREATED_INDEX,
            ScanIndexForward=False,
            **kwargs,
        )
        for page in pages:
            yield from page["Items"]

    def create(self, now: datetime | None = None) -> ScanJobDto:
        now = now or datetime.now(UTC)
        item = {
            "id": str(uuid.uuid4()),
            "kind": KIND,
            "status": ScanJobStatus.CREATED.value,
            "createdAt": _iso(now),
            "expiresAt": int((now + RETENTION).timestamp()),
        }
        self._table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        return to_dto(item, now)

    def get(self, job_id: str, now: datetime | None = None) -> ScanJobDto:
        item = self._table.get_item(Key={"id": job_id}).get("Item")
        if item is None:
            raise ScanJobNotFound(job_id)
        return to_dto(item, now or datetime.now(UTC))

    def report(
        self, job_id: str, status: ScanJobStatus, error: str | None = None, now: datetime | None = None
    ) -> ScanJobDto:
        """Records a status from the sync job. Creates the job when it is unknown (scheduled runs)."""
        now = now or datetime.now(UTC)
        values: dict[str, Any] = {
            ":status": status.value,
            ":kind": KIND,
            ":now": _iso(now),
            ":expires": int((now + RETENTION).timestamp()),
        }
        sets = [
            "#status = :status",
            "kind = :kind",
            "createdAt = if_not_exists(createdAt, :now)",
            "expiresAt = if_not_exists(expiresAt, :expires)",
        ]
        removes = []
        if status is ScanJobStatus.RUNNING:
            removes.append("finishedAt")
        else:
            sets.append("finishedAt = :now")
        if error and status is ScanJobStatus.FAILED:
            sets.append("#error = :error")
            values[":error"] = error
        else:
            removes.append("#error")
        update = f"SET {', '.join(sets)}" + (f" REMOVE {', '.join(removes)}" if removes else "")
        response = self._table.update_item(
            Key={"id": job_id},
            UpdateExpression=update,
            ExpressionAttributeNames={"#status": "status", "#error": "error"},
            ExpressionAttributeValues=values,
            ReturnValues="ALL_NEW",
        )
        return to_dto(response["Attributes"], now)

    def find_active(self, now: datetime | None = None) -> ScanJobDto | None:
        """Newest job created or running and not timed out, if any."""
        now = now or datetime.now(UTC)
        items = self._newest_first(
            KeyConditionExpression=Key("kind").eq(KIND) & Key("createdAt").gt(_iso(now - JOB_TIMEOUT)),
            FilterExpression=Attr("status").is_in([status.value for status in ACTIVE]),
        )
        item = next(items, None)
        return to_dto(item, now) if item else None

    def latest_succeeded(self, now: datetime | None = None) -> ScanJobDto | None:
        items = self._newest_first(
            KeyConditionExpression=Key("kind").eq(KIND),
            FilterExpression=Attr("status").eq(ScanJobStatus.SUCCEEDED.value),
        )
        item = next(items, None)
        return to_dto(item, now or datetime.now(UTC)) if item else None
