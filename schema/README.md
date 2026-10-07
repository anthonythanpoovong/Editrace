# Schema

Template JSON Schema — the single source of truth for the video template format. Every field is explained in [`docs/schema.md`](../docs/schema.md).

## Files

- `template.schema.json` — JSON Schema (2020-12) defining the template structure
- `examples/` — Hand-authored templates that must validate
- `examples/invalid/` — Single-defect fixtures that must be rejected; `EXPECTED` lists the error each one must produce
- `check-invalid.sh` — Checks the invalid fixtures are rejected, for the stated reason
- `check-docs.sh` — Checks every schema field and type is documented in `docs/schema.md`

## Rules

- Time is integer frames on one rational timebase (`source.fps`), never float seconds.
- Templates hold slots, never media or audio.
- Every detected element carries `confidence` and `provenance`.
- Change the schema with `/schema-change`. Generated types are never hand-written.

## Validate locally

```sh
pip install check-jsonschema
check-jsonschema --check-metaschema schema/template.schema.json
check-jsonschema --schemafile schema/template.schema.json schema/examples/*.json
schema/check-invalid.sh
schema/check-docs.sh
```
