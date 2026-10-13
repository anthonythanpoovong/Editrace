# Regenerates every type from schema/template.schema.json (#2). CI runs `make codegen` and fails if the output changed,
# so after editing the schema run it and commit the result. Needs uv (https://docs.astral.sh/uv/) and Node.
UV ?= uv

.PHONY: codegen codegen-python codegen-web

codegen: codegen-python codegen-web

# Pydantic models for workers/ and exporters/. OpenModel keeps unknown fields (docs/schema.md, forward compatibility).
codegen-python:
	$(UV) sync --quiet
	$(UV) run datamodel-codegen \
		--input schema/template.schema.json --input-file-type jsonschema \
		--output editrace_schema/models.py \
		--output-model-type pydantic_v2.BaseModel --base-class editrace_schema._base.OpenModel \
		--target-python-version 3.11 --use-annotated --field-constraints \
		--use-standard-collections --use-union-operator --use-title-as-name --capitalise-enum-members \
		--use-double-quotes --formatters ruff-check ruff-format --disable-timestamp

# TypeScript types and Zod schemas for web/ and the MCP tools.
codegen-web:
	cd web && npm run codegen
