// Round-trip tests for the generated Zod schema and types (#2). The Python side has the same tests in
// editrace_schema/test_models.py, so TS/Zod and Pydantic are held to the same examples.
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import type { Template } from "./template";
import { templateSchema } from "./template.zod";

const schemaDir = resolve(import.meta.dirname, "../../../schema");
const load = (dir: string) =>
  readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .sort()
    .map((name) => ({ name, document: JSON.parse(readFileSync(resolve(dir, name), "utf8")) }));
const examples = load(resolve(schemaDir, "examples"));
const invalid = load(resolve(schemaDir, "examples/invalid"));

// Constraints the generated Zod can't express (it has no if/then). The JSON Schema validator (schema/check-invalid.sh)
// still rejects these. Don't add to this list to make a test pass: fix the schema or the generator. A fixture Zod
// starts rejecting must come off the list (the test below fails).
const knownGaps: Record<string, string> = {
  "missing-slots.json": "if/then: a video track needs slots",
  "vfr-without-conform.json": "if/then: variable frame rate needs conform",
};

describe("generated Zod schema", () => {
  test.each(examples)("$name round-trips without loss", ({ document }) => {
    // Assigning to Template also checks that the Zod output type and the generated TS type agree.
    const parsed: Template = templateSchema.parse(document);
    expect(parsed).toEqual(document);
  });

  test("unknown fields survive a rewrite", () => {
    const document = structuredClone(examples[0].document);
    document.future_field = { added_in: "0.2.0" };
    document.tracks[0].future_track_field = [1, 2, 3];
    document.source.future_source_field = "kept";
    expect(templateSchema.parse(document)).toEqual(document);
  });

  test("sound_ref stays closed", () => {
    const withSound = examples.find(({ document }) => document.sound_ref);
    expect(withSound, "no example has a sound_ref to test with").toBeDefined();
    const document = structuredClone(withSound!.document);
    document.sound_ref.audio = "base64...";
    expect(templateSchema.safeParse(document).success).toBe(false);
  });

  test("rejects the forward-compat vector", () => {
    // Readers skip the unknown enum value (read-template.test.ts). Writers stay strict (docs/schema.md), so the same
    // document, from a newer minor, must not parse as a template.
    const { document } = JSON.parse(readFileSync(resolve(schemaDir, "test-vectors/forward-compat.json"), "utf8"));
    expect(templateSchema.safeParse(document).success).toBe(false);
  });

  test.each(invalid)("invalid fixture $name is rejected", ({ name, document }) => {
    const accepted = templateSchema.safeParse(document).success;
    // Still accepted today if it's a known gap. If this fails, the gap closed: remove it from knownGaps.
    expect(accepted).toBe(name in knownGaps);
  });

  test("known gaps name real fixtures", () => {
    const names = invalid.map(({ name }) => name);
    for (const gap of Object.keys(knownGaps)) expect(names).toContain(gap);
  });
});
