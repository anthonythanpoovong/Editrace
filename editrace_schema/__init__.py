"""The Editrace template models, generated from schema/template.schema.json by `make codegen`.

Never edit models.py or reader_models.py by hand: change the schema and regenerate.

- `Template` is strict, for writers (workers, exporters writing a template).
- `read_template` is for readers: it tolerates enum values from a newer minor version and reports them as skipped.
"""

from editrace_schema.models import EditraceTemplate as Template
from editrace_schema.reader import ReadResult, Skipped, read_template
from editrace_schema.reader_models import EditraceTemplate as ReaderTemplate

__all__ = ["ReadResult", "ReaderTemplate", "Skipped", "Template", "read_template"]
