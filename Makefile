# Regenerates every type from schema/template.schema.json (#2). CI runs `make codegen` and fails if the output changed,
# so after editing the schema run it and commit the result. Needs uv (https://docs.astral.sh/uv/) and Node.
UV ?= uv

.PHONY: codegen codegen-python codegen-web

codegen: codegen-python codegen-web

GEN_FLAGS = --input-file-type jsonschema --output-model-type pydantic_v2.BaseModel \
	--base-class editrace_schema._base.OpenModel --target-python-version 3.11 --use-annotated --field-constraints \
	--use-standard-collections --use-union-operator --use-title-as-name --capitalise-enum-members \
	--use-double-quotes --formatters ruff-check ruff-format --disable-timestamp

# schema/VERSION becomes editrace_schema/version.py (and web/lib/generated/schema-version.ts), so readers know which
# version they support. Pydantic models for workers/ and exporters/. OpenModel keeps unknown fields (docs/schema.md, forward compatibility).
# models.py is strict, for writers. reader_models.py is the same schema with enums relaxed to strings, for readers
# (scripts/reader_schema.py): an unknown enum value from a newer minor version must not fail the whole template (#206).
codegen-python:
	$(UV) sync --quiet
	$(UV) run python scripts/schema_version.py schema/VERSION > editrace_schema/version.py
	$(UV) run datamodel-codegen $(GEN_FLAGS) --input schema/template.schema.json --output editrace_schema/models.py
	$(UV) run python scripts/reader_schema.py schema/template.schema.json | \
		$(UV) run datamodel-codegen $(GEN_FLAGS) --output editrace_schema/reader_models.py

# TypeScript types and Zod schemas for web/ and the MCP tools.
codegen-web:
	cd web && npm run codegen
