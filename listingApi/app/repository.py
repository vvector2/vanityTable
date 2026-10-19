"""DynamoDB access for the Listings table. See docs/llstingApi.md, section DynamoDB."""

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from app.models import CreateListingRequest, ListingDto, ListingStatus

STATUS_INDEX = "status-firstSeenAt-index"
# Fixed namespace for listing ids. Changing it would give known listings new ids.
LISTING_ID_NAMESPACE = uuid.UUID("5b0f6d2e-8c7a-4e1b-9a3d-2f4c6e8a1b0d")


class ListingNotFound(Exception):
    pass


class ListingAlreadyExists(Exception):
    pass


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def listing_id_for(source_id: str) -> str:
    """Internal id of a listing, derived from its source id.

    Deterministic, so the same source id always maps to the same item and the
    `attribute_not_exists(id)` condition makes creates idempotent without a second index.
    """
    return str(uuid.uuid5(LISTING_ID_NAMESPACE, source_id))


def _is_condition_failure(error: ClientError) -> bool:
    return error.response["Error"]["Code"] == "ConditionalCheckFailedException"


def to_dto(item: dict[str, Any]) -> ListingDto:
    price = item.get("price")
    return ListingDto(
        id=item["id"],
        source_id=item.get("sourceId"),
        title=item.get("title", ""),
        price=int(price) if isinstance(price, Decimal) else price,
        currency=item.get("currency", "PLN"),
        location=item.get("location"),
        url=item.get("url", ""),
        images=list(item.get("images", [])),
        description=item.get("description"),
        status=item["status"],
        first_seen_at=item["firstSeenAt"],
        updated_at=item.get("updatedAt", item["firstSeenAt"]),
    )


class ListingRepository:
    def __init__(self, table: Any) -> None:
        self._table = table

    def _query_status(self, status: ListingStatus, **kwargs: Any) -> Any:
        """Queries the status index across all result pages (Query reads at most 1 MB per call).

        The paginator comes from the resource's client, so it accepts Key() conditions
        and returns plain Python values like Table.query does.
        """
        paginator = self._table.meta.client.get_paginator("query")
        return paginator.paginate(
            TableName=self._table.name,
            IndexName=STATUS_INDEX,
            KeyConditionExpression=Key("status").eq(status.value),
            **kwargs,
        )

    def count(self, status: ListingStatus) -> int:
        return sum(page["Count"] for page in self._query_status(status, Select="COUNT"))

    def list_page(self, status: ListingStatus, page: int, page_size: int) -> list[ListingDto]:
        """Returns one page, newest first. Skips earlier pages, which is fine at MVP scale."""
        skip = (page - 1) * page_size
        pages = self._query_status(
            status, ScanIndexForward=False, PaginationConfig={"MaxItems": skip + page_size}
        )
        items = pages.build_full_result()["Items"]
        return [to_dto(item) for item in items[skip:]]

    def set_status(self, listing_id: str, status: ListingStatus) -> ListingDto:
        now = utc_now()
        try:
            response = self._table.update_item(
                Key={"id": listing_id},
                UpdateExpression="SET #status = :status, updatedAt = :now",
                ConditionExpression="attribute_exists(id)",
                ExpressionAttributeNames={"#status": "status"},
                ExpressionAttributeValues={":status": status.value, ":now": now},
                ReturnValues="ALL_NEW",
            )
        except ClientError as error:
            if _is_condition_failure(error):
                raise ListingNotFound(listing_id) from error
            raise
        return to_dto(response["Attributes"])

    def create(self, listing: CreateListingRequest) -> ListingDto:
        """Inserts a listing as `new`. Never overwrites a known listing, so decisions are kept."""
        now = utc_now()
        item = {
            key: value
            for key, value in listing.model_dump(by_alias=True).items()
            if value is not None
        }
        item.update(
            id=listing_id_for(listing.source_id),
            status=ListingStatus.NEW.value,
            firstSeenAt=now,
            updatedAt=now,
        )
        try:
            self._table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        except ClientError as error:
            if _is_condition_failure(error):
                raise ListingAlreadyExists(listing.source_id) from error
            raise
        return to_dto(item)

    def delete(self, listing_id: str) -> None:
        try:
            self._table.delete_item(Key={"id": listing_id}, ConditionExpression="attribute_exists(id)")
        except ClientError as error:
            if _is_condition_failure(error):
                raise ListingNotFound(listing_id) from error
            raise
