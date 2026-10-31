"""DynamoDB access for the Listings table. See docs/llstingApi.md, section DynamoDB."""

from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from app.core.listing import Listing, ListingCounts, ListingStatus, NewListing

# Keyed by searchStatus (`<searchId>#<status>`): a GSI key is one attribute, so the pair is stored.
STATUS_INDEX = "searchStatus-firstSeenAt-index"


class ListingNotFound(Exception):
    pass


class ListingAlreadyExists(Exception):
    pass


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def search_status(search_id: str, status: ListingStatus) -> str:
    return f"{search_id}#{status.value}"


def _is_condition_failure(error: ClientError) -> bool:
    return error.response["Error"]["Code"] == "ConditionalCheckFailedException"


def to_listing(item: dict[str, Any]) -> Listing:
    price = item.get("price")
    return Listing(
        id=item["id"],
        search_id=item.get("searchId"),
        source_id=item.get("sourceId"),
        title=item.get("title", ""),
        price=int(price) if isinstance(price, Decimal) else price,
        currency=item.get("currency", "PLN"),
        location=item.get("location"),
        url=item.get("url", ""),
        images=list(item.get("images", [])),
        description=item.get("description"),
        status=ListingStatus(item["status"]),
        first_seen_at=item["firstSeenAt"],
        updated_at=item.get("updatedAt", item["firstSeenAt"]),
    )


class ListingRepository:
    def __init__(self, table: Any) -> None:
        self._table = table

    def _query_status(self, search_id: str, status: ListingStatus, **kwargs: Any) -> Any:
        """Queries one search's status across all result pages (Query reads at most 1 MB per call).

        The paginator comes from the resource's client, so it accepts Key() conditions
        and returns plain Python values like Table.query does.
        """
        paginator = self._table.meta.client.get_paginator("query")
        return paginator.paginate(
            TableName=self._table.name,
            IndexName=STATUS_INDEX,
            KeyConditionExpression=Key("searchStatus").eq(search_status(search_id, status)),
            **kwargs,
        )

    def count(self, search_id: str, status: ListingStatus) -> int:
        return sum(page["Count"] for page in self._query_status(search_id, status, Select="COUNT"))

    def counts(self, search_id: str) -> ListingCounts:
        return ListingCounts(**{status.value: self.count(search_id, status) for status in ListingStatus})

    def list_page(self, search_id: str, status: ListingStatus, page: int, page_size: int) -> list[Listing]:
        """Returns one page, newest first. Skips earlier pages, which is fine at MVP scale."""
        skip = (page - 1) * page_size
        pages = self._query_status(
            search_id, status, ScanIndexForward=False, PaginationConfig={"MaxItems": skip + page_size}
        )
        items = pages.build_full_result()["Items"]
        return [to_listing(item) for item in items[skip:]]

    def set_status(self, listing_id: str, status: ListingStatus) -> Listing:
        """Sets status and searchStatus. An update cannot build searchStatus from searchId, so the
        item is read first; the condition makes sure it is still the same search's listing."""
        item = self._table.get_item(Key={"id": listing_id}, ProjectionExpression="searchId").get("Item")
        if item is None:
            raise ListingNotFound(listing_id)
        search_id = item["searchId"]
        now = utc_now()
        try:
            response = self._table.update_item(
                Key={"id": listing_id},
                UpdateExpression="SET #status = :status, searchStatus = :searchStatus, updatedAt = :now",
                ConditionExpression="searchId = :searchId",
                ExpressionAttributeNames={"#status": "status"},
                ExpressionAttributeValues={
                    ":status": status.value,
                    ":searchStatus": search_status(search_id, status),
                    ":searchId": search_id,
                    ":now": now,
                },
                ReturnValues="ALL_NEW",
            )
        except ClientError as error:
            if _is_condition_failure(error):
                raise ListingNotFound(listing_id) from error
            raise
        return to_listing(response["Attributes"])

    def create(self, listing: NewListing) -> Listing:
        """Inserts a listing as `new`. Never overwrites a known listing, so decisions are kept.

        `id` is derived from the search and source id, so `attribute_not_exists(id)` makes the
        create idempotent without a second index."""
        now = utc_now()
        item = {
            "id": listing.id,
            "searchId": listing.search_id,
            "sourceId": listing.source_id,
            "title": listing.title,
            "price": listing.price,
            "currency": listing.currency,
            "location": listing.location,
            "url": listing.url,
            "images": listing.images,
            "description": listing.description,
            "status": ListingStatus.NEW.value,
            "searchStatus": search_status(listing.search_id, ListingStatus.NEW),
            "firstSeenAt": now,
            "updatedAt": now,
        }
        item = {key: value for key, value in item.items() if value is not None}
        try:
            self._table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        except ClientError as error:
            if _is_condition_failure(error):
                raise ListingAlreadyExists(listing.source_id) from error
            raise
        return to_listing(item)

    def delete_for_search(self, search_id: str) -> int:
        """Deletes all listings of a search and returns how many were deleted."""
        ids = [
            item["id"]
            for status in ListingStatus
            for page in self._query_status(search_id, status, ProjectionExpression="id")
            for item in page["Items"]
        ]
        # batch_writer sends up to 25 deletes per call and resends unprocessed ones.
        with self._table.batch_writer() as batch:
            for listing_id in ids:
                batch.delete_item(Key={"id": listing_id})
        return len(ids)

    def delete(self, listing_id: str) -> None:
        try:
            self._table.delete_item(Key={"id": listing_id}, ConditionExpression="attribute_exists(id)")
        except ClientError as error:
            if _is_condition_failure(error):
                raise ListingNotFound(listing_id) from error
            raise
