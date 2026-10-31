"""DTO base and shared DTOs. JSON uses camelCase field names, Python uses snake_case."""

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class ErrorDto(CamelModel):
    error: str
    message: str
