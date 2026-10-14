"""The Editrace template models, generated from schema/template.schema.json by `make codegen`.

Never edit models.py or reader_models.py by hand: change the schema and regenerate.

- `Template` is strict, for writers (workers, exporters writing a template).
- `read_template` is for readers: it tolerates enum values from a newer minor version and reports them as skipped,
  and rejects a higher major version.
"""

from editrace_schema.models import EditraceTemplate as Template
from editrace_schema.reader import (
    Migration,
    ReadResult,
    Skipped,
    UnsupportedVersionError,
    migrate_to_supported_version,
    read_template,
)
from editrace_schema.reader_models import EditraceTemplate as ReaderTemplate

__all__ = [
    "Migration",
    "ReadResult",
    "ReaderTemplate",
    "Skipped",
    "Template",
    "UnsupportedVersionError",
    "migrate_to_supported_version",
    "read_template",
]
