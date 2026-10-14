// Tests for readTemplate (#206). The Python side has the same cases in editrace_schema/test_reader.py.
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { templateSchema } from "./generated/template.zod";
import { KNOWN_TRACK_KINDS, SCHEMA_VERSION } from "./generated/constants";
import { migrateToSupportedVersion, readTemplate, UnsupportedVersionError } from "./read-template";

const schemaDir = resolve(import.meta.dirname, "../../schema");
const json = (...parts: string[]) => JSON.parse(readFileSync(resolve(schemaDir, ...parts), "utf8"));
const vector = json("test-vectors", "forward-compat.json").document;
const versionCases: {
  name: string;
  reader: string;
  migrations: number[];
  document: string;
  expected: "accept" | "reject" | "accept_via_migration";
  error_mentions?: string[];
}[] = json("test-vectors", "versions.json").cases;
const files = (dir: string) => readdirSync(resolve(schemaDir, dir)).filter((name) => name.endsWith(".json")).sort();

describe("readTemplate", () => {
  test("the forward-compat vector reports the unknown transition and the unknown track kind", () => {
    // The vector has both: an unknown transition type and an unknown track kind (docs/schema.md skips both).
    expect(readTemplate(vector).skipped).toEqual([
      { path: ["tracks", 0, "transitions", 1], field: "type", value: "hologram" },
      { path: ["tracks", 1], field: "kind", value: "hologram" },
    ]);
  });

  test("known track kinds come from the schema, and a known kind is never reported", () => {
    expect([...KNOWN_TRACK_KINDS].sort()).toEqual(["captions", "text", "video"]);
    const document = json("examples", files("examples")[0]);
    expect(document.tracks.every((track: { kind: string }) => KNOWN_TRACK_KINDS.has(track.kind))).toBe(true);
    expect(readTemplate(document).skipped).toEqual([]);
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
    expect(readTemplate(document).skipped.filter((s) => s.field === "type").map((s) => s.value).sort()).toEqual(["hologram", "star-wipe"]);
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

// ---- versions (ADR 0002): the same cases schema/check-vectors.sh and the Python tests run -------------------------

describe("version rules", () => {
  test.each(versionCases)("$name", (c) => {
    const document = { schema_version: c.document };
    const migrations = Object.fromEntries(c.migrations.map((major) => [major, (doc: object) => ({ ...doc, migrated: true })]));
    if (c.expected === "reject") {
      const run = () => migrateToSupportedVersion(c.reader, document, migrations);
      expect(run).toThrow(UnsupportedVersionError);
      for (const version of c.error_mentions ?? []) expect(run).toThrow(version);
    } else if (c.expected === "accept_via_migration") {
      expect(migrateToSupportedVersion(c.reader, document, migrations).migrated).toBe(true);
    } else {
      expect(migrateToSupportedVersion(c.reader, document, migrations)).toEqual(document);
    }
  });

  test("a higher major is rejected before anything else is read", () => {
    // Its structure may not match these types, so no other error should hide the real reason.
    const major = Number(SCHEMA_VERSION.split(".")[0]) + 1;
    const document = { schema_version: `${major}.0.0`, tracks: "not even a list" };
    expect(() => readTemplate(document)).toThrow(new RegExp(`${major}\\.0\\.0.*${SCHEMA_VERSION}`));
    expect(() => readTemplate(document)).toThrow(UnsupportedVersionError);
  });

  test("a missing or malformed version is left to validation", () => {
    for (const document of [{ source: {} }, { schema_version: "banana" }, { schema_version: 3 }]) {
      expect(() => readTemplate(document)).toThrow();
      expect(() => readTemplate(document)).not.toThrow(UnsupportedVersionError);
    }
  });

  test("the vector is read by the version this code supports", () => {
    const reader = json("test-vectors", "forward-compat.json").reader as string;
    expect(reader.split(".")[0]).toBe(SCHEMA_VERSION.split(".")[0]);
  });

  test("schema/VERSION matches the generated constant and the examples", () => {
    expect(readFileSync(resolve(schemaDir, "VERSION"), "utf8").trim()).toBe(SCHEMA_VERSION);
    const current = SCHEMA_VERSION.split(".").map(Number);
    for (const name of files("examples")) {
      const written = (json("examples", name).schema_version as string).split(".").map(Number);
      const notNewer =
        written[0] < current[0] || (written[0] === current[0] && (written[1] < current[1] || (written[1] === current[1] && written[2] <= current[2])));
      expect(written[0], name).toBe(current[0]);
      expect(notNewer, name).toBe(true);
    }
  });
});
