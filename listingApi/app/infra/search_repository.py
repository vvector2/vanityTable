"""DynamoDB access for the Searches table. See docs/llstingApi.md, section DynamoDB.

A search holds the criteria the sync job scans OLX with; its listings live in the Listings
table under its `searchId`. Counts per status come from the listings repository.
"""

import uuid
from collections.abc import Iterator
from decimal import Decimal
from typing import Any

from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from app.core.search import Criteria, Location, NewSearch, Search, SearchStatus
from app.infra.listing_repository import utc_now

USER_INDEX = "userId-createdAt-index"
STATUS_INDEX = "status-createdAt-index"


class SearchNotFound(Exception):
    pass


def _int(value: Any) -> int | None:
    # DynamoDB returns numbers as Decimal.
    return int(value) if isinstance(value, Decimal) else value


def criteria_to_item(criteria: Criteria) -> dict[str, Any]:
    """Stored map with camelCase keys; unset criteria are left out."""
    item: dict[str, Any] = {
        "keywords": criteria.keywords,
        "excludeKeywords": criteria.exclude_keywords,
        "priceMin": criteria.price_min,
        "priceMax": criteria.price_max,
        "description": criteria.description,
    }
    if criteria.location:
        item["location"] = {"city": criteria.location.city, "radiusKm": criteria.location.radius_km}
        item["location"] = {key: value for key, value in item["location"].items() if value is not None}
    return {key: value for key, value in item.items() if value is not None}


def criteria_from_item(item: dict[str, Any]) -> Criteria:
    location = item.get("location")
    return Criteria(
        keywords=list(item["keywords"]),
        exclude_keywords=list(item.get("excludeKeywords", [])),
        price_min=_int(item.get("priceMin")),
        price_max=_int(item.get("priceMax")),
        location=Location(city=location["city"], radius_km=_int(location.get("radiusKm"))) if location else None,
        description=item.get("description"),
    )


def to_search(item: dict[str, Any]) -> Search:
    return Search(
        id=item["id"],
        user_id=item["userId"],
        title=item["title"],
        criteria=criteria_from_item(item["criteria"]),
        status=SearchStatus(item["status"]),
        created_at=item["createdAt"],
        updated_at=item.get("updatedAt", item["createdAt"]),
    )


class SearchRepository:
    def __init__(self, table: Any) -> None:
        self._table = table

    def _newest_first(self, index: str, key: Any) -> Iterator[Search]:
        paginator = self._table.meta.client.get_paginator("query")
        pages = paginator.paginate(
            TableName=self._table.name,
            IndexName=index,
            KeyConditionExpression=key,
            ScanIndexForward=False,
        )
        for page in pages:
            for item in page["Items"]:
                yield to_search(item)

    def list_for_user(self, user_id: str) -> list[Search]:
        return list(self._newest_first(USER_INDEX, Key("userId").eq(user_id)))

    def list_by_status(self, status: SearchStatus) -> list[Search]:
        """All users' searches with this status; the sync job reads the active ones."""
        return list(self._newest_first(STATUS_INDEX, Key("status").eq(status.value)))

    def get(self, search_id: str) -> Search:
        item = self._table.get_item(Key={"id": search_id}).get("Item")
        if item is None:
            raise SearchNotFound(search_id)
        return to_search(item)

    def exists(self, search_id: str) -> bool:
        return "Item" in self._table.get_item(Key={"id": search_id}, ProjectionExpression="id")

    def create(self, user_id: str, search: NewSearch) -> Search:
        now = utc_now()
        item = {
            "id": str(uuid.uuid4()),
            "userId": user_id,
            "title": search.title,
            "criteria": criteria_to_item(search.criteria),
            "status": SearchStatus.ACTIVE.value,
            "createdAt": now,
            "updatedAt": now,
        }
        self._table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        return to_search(item)

    def delete(self, search_id: str) -> None:
        try:
            self._table.delete_item(Key={"id": search_id}, ConditionExpression="attribute_exists(id)")
        except ClientError as error:
            if error.response["Error"]["Code"] == "ConditionalCheckFailedException":
                raise SearchNotFound(search_id) from error
            raise
