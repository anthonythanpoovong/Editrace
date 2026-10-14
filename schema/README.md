# Schema

Template JSON Schema — the single source of truth for the video template format. Every field is explained in [`docs/schema.md`](../docs/schema.md).

## Files

- `template.schema.json` — JSON Schema (2020-12) defining the template structure
- `VERSION` — the version the schema is at (semver). Bump it with every schema change; `make codegen` passes it to the readers
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
| Pydantic (strict, for writers) | `editrace_schema/models.py` | `from editrace_schema import Template` in `workers/` and `exporters/` |
| Pydantic (reader) | `editrace_schema/reader_models.py` | `from editrace_schema import read_template` |
| TypeScript | `web/lib/generated/template.ts` | `import type { Template } from "@/lib/generated/template"` |
| Zod (strict, for writers) | `web/lib/generated/template.zod.ts` | `templateSchema`, for MCP tool inputs and outputs |
| Zod (reader) | `web/lib/generated/template.reader.zod.ts` | `readTemplate` in `web/lib/read-template.ts` |

Never edit those files. Change the schema (`/schema-change`) and regenerate. Objects stay open, so a template from a newer minor version keeps its unknown fields on a read and rewrite; `sound_ref` is closed.

**Writers are strict, readers are not.** `Template` and `templateSchema` reject an unknown enum value, so a worker can't save one. A reader must not fail a whole template on a value from a newer minor version (`docs/schema.md`), so use `read_template` (Python) or `readTemplate` (TypeScript) to load a template you didn't write. They return the template plus the elements to skip (an unknown enum value, or a track of an unknown `kind`), e.g. `Skipped(path=("tracks", 0, "transitions", 1), field="type", value="hologram")`. They also apply the version rules from `docs/schema.md`: a higher major version raises `UnsupportedVersionError` naming both versions, and so does a lower one unless you pass `migrations`. The reader models are the same schema with only the `enum` keyword removed (`scripts/reader_schema.py`), so patterns, ranges and required fields still apply, and any other error still raises.

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
