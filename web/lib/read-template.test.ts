// Tests for readTemplate (#206). The Python side has the same cases in editrace_schema/test_reader.py.
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { templateSchema } from "./generated/template.zod";
import { readTemplate } from "./read-template";

const schemaDir = resolve(import.meta.dirname, "../../schema");
const json = (...parts: string[]) => JSON.parse(readFileSync(resolve(schemaDir, ...parts), "utf8"));
const vector = json("test-vectors", "forward-compat.json").document;
const files = (dir: string) => readdirSync(resolve(schemaDir, dir)).filter((name) => name.endsWith(".json")).sort();

describe("readTemplate", () => {
  test("the forward-compat vector loads and reports the unknown transition", () => {
    expect(readTemplate(vector).skipped).toEqual([
      { path: ["tracks", 0, "transitions", 1], field: "type", value: "hologram" },
    ]);
  });

  test("unknown values and fields survive a rewrite", () => {
    expect(readTemplate(vector).template).toEqual(vector);
  });

  test("the strict schema still rejects the vector", () => {
    // Writers stay strict: a worker must not be able to save an unknown enum value.
    expect(templateSchema.safeParse(vector).success).toBe(false);
  });

  test.each(files("examples"))("valid example %s reports nothing skipped", (name) => {
    const document = json("examples", name);
    const result = readTemplate(document);
    expect(result.skipped).toEqual([]);
    expect(result.template).toEqual(document);
  });

  test("every unknown enum value is reported", () => {
    const document = structuredClone(vector);
    document.tracks[0].transitions[0].type = "star-wipe";
    expect(readTemplate(document).skipped.map((s) => s.value).sort()).toEqual(["hologram", "star-wipe"]);
  });

  test("another problem next to an unknown value still throws", () => {
    const document = structuredClone(vector);
    document.tracks[0].transitions[0].confidence = 7; // above the maximum of 1
    expect(() => readTemplate(document)).toThrow();
  });

  test("an invalid fixture is not let through, except the one that only has an unknown enum value", () => {
    // Same known gaps as template.test.ts: Zod can't express the if/then rules, so these still load.
    const gaps = ["missing-slots.json", "vfr-without-conform.json"];
    for (const name of files("examples/invalid")) {
      const document = json("examples", "invalid", name);
      if (name === "unknown-transition-type.json") {
        expect(readTemplate(document).skipped.map((s) => s.value)).toEqual(["sparkle"]);
      } else if (gaps.includes(name)) {
        expect(() => readTemplate(document), name).not.toThrow();
      } else {
        expect(() => readTemplate(document), name).toThrow();
      }
    }
  });
});
