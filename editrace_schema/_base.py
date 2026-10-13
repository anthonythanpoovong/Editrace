"""Base class for the generated models.

Objects in the template schema are open: a template from a newer minor version can carry fields this code doesn't know,
and a tool that reads and rewrites it must keep them (docs/schema.md, "Versions and forward compatibility"). Pydantic
drops unknown fields by default, so the generated models inherit this class, which keeps them. A model the schema closes
(`additionalProperties: false`, like `sound_ref`) sets `extra="forbid"` itself, which wins over this.
"""

from pydantic import BaseModel, ConfigDict


class OpenModel(BaseModel):
    model_config = ConfigDict(extra="allow")
