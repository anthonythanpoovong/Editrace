# Schema

Template JSON Schema — the single source of truth for the video template format. Every field is explained in [`docs/schema.md`](../docs/schema.md).

## Files

- `template.schema.json` — JSON Schema (2020-12) defining the template structure
- `examples/` — Hand-authored templates that must validate
- `examples/invalid/` — Single-defect fixtures that must be rejected; `EXPECTED` lists the error each one must produce
- `test-vectors/` — Shared fixtures every adapter and reader must reproduce: rescaling, timecode, versions, forward compatibility
- `check-vectors.sh` — Runs a reference implementation against the test vectors
- `check-invalid.sh` — Checks the invalid fixtures are rejected, for the stated reason
- `check-docs.sh` — Checks every schema field and type is documented in `docs/schema.md`

## Rules

- Time is integer frames on one rational timebase (`source.fps`), never float seconds.
- Templates hold slots, never media or audio.
- Every detected element carries `confidence` and `provenance`.
- Change the schema with `/schema-change`. Generated types are never hand-written.

## Generated types

`make codegen` (needs [uv](https://docs.astral.sh/uv/) and Node) regenerates every type from `template.schema.json`. Commit the result: CI runs the same command and fails if anything changed.

| Target | Generated file | Use it from |
|---|---|---|
| Pydantic | `editrace_schema/models.py` | `from editrace_schema import Template` in `workers/` and `exporters/` |
| TypeScript | `web/lib/generated/template.ts` | `import type { Template } from "@/lib/generated/template"` |
| Zod | `web/lib/generated/template.zod.ts` | `templateSchema`, for MCP tool inputs and outputs |

Never edit those files. Change the schema (`/schema-change`) and regenerate. Objects stay open, so a template from a newer minor version keeps its unknown fields on a read and rewrite; `sound_ref` is closed.

The generated types are weaker than the JSON Schema in a few places: neither Pydantic nor Zod enforces the `if/then` rules (a video track needs `slots`, a variable-frame-rate source needs `conform`), and Pydantic drops the `^https://` pattern on `sound_ref.link`. Writers should still validate with the JSON Schema (`schema/check-invalid.sh` shows how). The round-trip tests (`editrace_schema/test_models.py`, `web/lib/generated/template.test.ts`) list these gaps explicitly and fail if one closes without the list being updated.

## Validate locally

```sh
pip install check-jsonschema
check-jsonschema --check-metaschema schema/template.schema.json
check-jsonschema --schemafile schema/template.schema.json schema/examples/*.json
schema/check-invalid.sh
schema/check-docs.sh
schema/check-vectors.sh
```
