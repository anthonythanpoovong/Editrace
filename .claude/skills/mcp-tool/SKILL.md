---
name: mcp-tool
description: Add or change a tool on Editrace's remote MCP server (#27) or the local Editrace Bridge (#32) — generated Zod schemas, auth and entitlements, per-user data access, audit logging, and MCP Inspector/client testing. Use for work like "add export_template", "new Bridge tool", "change get_elements parameters".
---

# Add or change an MCP tool

Editrace has **two MCP servers** (a Key Decision):
- **Remote MCP server (#27):** hosted, Streamable HTTP, OAuth via Supabase Auth, personal tokens as a fallback (#37). It reads templates and makes exports.
- **Editrace Bridge (#32):** local stdio server that drives desktop editors through adapters. It never holds Editrace data longer than needed.

Decide which one the tool belongs on first: anything that touches the user's editor goes on the **Bridge**; everything else goes on the **remote** server.

## 0. Preflight
- The target server exists in the repo (remote: in `web/`, per the README; Bridge: its own folder once #29 decides the language). If not, stop and point to #27, #32 or #29.
- Generated Zod schemas from the template schema exist (#2). Tool I/O that includes template data must use them.
- Check the planned tool list (wiki `MCP-and-Editrace-Bridge`, `docs/plan.md` → MCP Design) so names and shapes stay consistent.

## 1. Design (confirm with the author)
- **Name:** `verb_noun`, snake_case, consistent with the existing tools (`list_templates`, `get_elements`, `apply_template`).
- **Description:** written for the model calling it: what it does, when to use it, and what it returns. Be specific.
- **Inputs:** minimal. Required vs optional, with defaults. Use IDs rather than free text where possible. Support time ranges in **frames**.
- **Output:** structured and bounded (paginate lists, filter large templates with `sections` or `type`). No raw media.
- **Read or write?** Tools with side effects (export, apply) must say so. Bridge `apply` tools must support a dry-run `plan`.

## 2. Implement
- Input and output schemas from the generated Zod types. **Never hand-write template shapes.**
- **Auth:** resolve the user from the OAuth token or personal token. Tokens are **hashed at rest** (#37).
- **Data access:** query as the user, so RLS applies. Never use the service role for user-scoped reads. Cross-user access must be impossible.
- **Entitlements and rate limits (#19):** check the plan before expensive work (exports, assistant calls).
- **Audit log:** record user, tool, arguments (redacted) and result status.
- **Errors:** clear, actionable messages. Never leak internals or other users' identifiers.
- **Bridge only:** go through the adapter interface (`detect / capabilities / plan / apply → report`); see `/editor-adapter`. Return what was applied, skipped or approximated.

## 3. Test
- Unit tests for input validation and auth failures (no token, bad token, another user's template ID → not found).
- **MCP Inspector:** list tools, call the tool with good and bad inputs.
- One real client: Claude Code or Claude Desktop (the #27 and #32 acceptance criteria).
- An RLS-through-MCP test: user B can't reach user A's template via this tool.

## 4. PR
The body includes the tool signature (name, inputs, output), auth and entitlement notes, an Inspector screenshot or transcript, and test output. After merge, `/sync-docs` updates the wiki tool tables and `docs/plan.md` → MCP Design.

## Rules
- Breaking a published tool contract (rename, remove, required-param change) needs an ADR (`/propose-adr`) and a deprecation path, because clients cache tool lists.
- Never return raw media or audio. Never use the service role on a user's behalf.
