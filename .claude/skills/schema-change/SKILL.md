---
name: schema-change
description: Safely change Editrace's template JSON Schema (schema/template.schema.json) — add or change fields/sections, regenerate TypeScript/Pydantic/Zod, update examples, and handle versioning/migration. Use for any edit to the template format, e.g. "add a field to slots", "change how captions are stored", or story #99. Routes breaking changes to /propose-adr.
---

# Change the template schema

`schema/template.schema.json` is the **single source of truth**. The TypeScript (web), Pydantic (workers, exporters) and Zod (MCP tools) types are **generated from it, never hand-written** (Key Decisions; #1, #2).

## 0. Preflight
- `schema/template.schema.json` must exist. If it doesn't, stop: this is #1.
- Codegen: a `Makefile` with a `codegen` target (#2). If it's missing, you can still edit the schema and examples, but say plainly that generated types can't be updated until #2 lands, and don't hand-write them as a stopgap.

## 1. Classify the change

| Kind | Examples | Path |
|---|---|---|
| **Additive** | New optional field, new optional section, new enum value that consumers can ignore | Continue here |
| **Breaking** | Rename/remove a field, make optional → required, change a type or unit, change enum meaning | **Stop → `/propose-adr`** with a migration plan, then come back |

If you're unsure, treat it as breaking.

## 2. Check the rules the schema must follow
- **Time is frames + rational fps**, never float seconds. Durations and positions are integer frames; fps is a rational (`num`/`den`).
- **Slots, not media.** No embedded media, URLs to user media, or audio. Sound is referenced by id, title, artist and link only.
- **Every detected element carries `confidence` and `provenance`** (detector, version).
- Bounding boxes are normalized (0–1).
- New fields get a `description`. Constrain them (`minimum`, `enum`, `pattern`) rather than leaving them free-form.

## 3. Edit
1. Change `schema/template.schema.json`.
2. Update or add at least one file in `schema/examples/` that exercises the new or changed part.
3. For **each new or changed constraint** (`required`, `minimum`/`maximum`, `enum`, `pattern`, `type`, `additionalProperties: false`), add an invalid fixture that breaks only that constraint:
   - Copy `schema/examples/01-simple-reel-30fps.json` into `schema/examples/invalid/<defect>.json` and introduce exactly one defect.
   - Add a line to `schema/examples/invalid/EXPECTED`: `<defect>.json|<text the validation error must contain>`. Pick text specific to this constraint, so the fixture fails for the right reason, not because of some other error.
   - If you loosened a constraint, update or remove the fixture that relied on it, and say why in the PR.
4. Validate locally (the same checks CI runs):
   ```sh
   pipx run check-jsonschema --check-metaschema schema/template.schema.json
   pipx run check-jsonschema --schemafile schema/template.schema.json schema/examples/*.json
   schema/check-invalid.sh   # needs check-jsonschema on PATH
   ```
5. Regenerate: `make codegen`. Commit the generated output. CI fails if generated code is stale.
6. Find consumers that need updating: search workers, exporters, web and MCP tools for the changed section and fix them in the same PR, or open follow-up issues.

## 4. Version
- Bump the schema's version per its versioning rule (see the wiki `Template-Schema` page). If none is defined yet, flag that as a TODO on #1 rather than inventing a scheme.
- Additive changes: old templates must still validate. Prove it by validating the existing examples unchanged.

## 5. PR
Title: `Schema: <change>`. The body covers the kind (additive or breaking + ADR link), the fields changed, consumers updated, examples added, invalid fixtures added (one per constraint), and the codegen result. Link the story (e.g. #99).

## Rules
- Never hand-edit generated files. Never add types by hand in `web/`, `workers/` or `exporters/`.
- Never mix a breaking change into an additive PR.
- After merge, `/sync-docs` updates the wiki `Template-Schema` page and `docs/plan.md` → Template Schema table.
