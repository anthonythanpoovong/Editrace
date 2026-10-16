// Reading a template that may come from a newer minor version (#206). The TypeScript counterpart of
// editrace_schema/reader.py: the strict `templateSchema` is for writers and rejects an unknown enum value, but
// docs/schema.md says a reader treats one as unsupported ("skipped") and never fails the whole template.
import { KNOWN_TRACK_KINDS, SCHEMA_VERSION } from "./generated/constants";
import { templateReaderSchema } from "./generated/template.reader.zod";
import { templateSchema } from "./generated/template.zod";

export type ReaderTemplate = ReturnType<typeof templateReaderSchema.parse>;

/** Takes a template document from an older major version and returns it in the reader's major version. */
export type Migration = (document: Record<string, unknown>) => Record<string, unknown>;

/** The template's major version isn't one this reader supports. The message names both versions. */
export class UnsupportedVersionError extends Error {
  override name = "UnsupportedVersionError";
}

const semver = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;

/**
 * Applies the version rules (docs/schema.md) to `document` for a reader that supports `reader`: the same major (any
 * minor or patch) passes through; a higher major throws; a lower major throws unless `migrations` has one for it.
 * A document without a well-formed `schema_version` is returned as is, so validation reports it.
 */
export function migrateToSupportedVersion(
  reader: string,
  document: Record<string, unknown>,
  migrations: Record<number, Migration> = {},
): Record<string, unknown> {
  const version = document.schema_version;
  if (typeof version !== "string" || !semver.test(version)) return document;
  const readerMajor = Number(reader.split(".")[0]);
  const documentMajor = Number(version.split(".")[0]);
  if (documentMajor > readerMajor) {
    throw new UnsupportedVersionError(`template is ${version}, reader supports ${reader}`);
  }
  if (documentMajor < readerMajor) {
    const migration = migrations[documentMajor];
    if (!migration) {
      throw new UnsupportedVersionError(`template is ${version}, reader is ${reader} and has no migration`);
    }
    return migration(document);
  }
  return document;
}

/** An element holding an enum value, or a track kind, this version of the schema doesn't know. */
export type Skipped = {
  /** Where the element is, e.g. ["tracks", 0, "transitions", 1] or ["tracks", 1]. */
  path: (string | number)[];
  /** The field with the unknown value, e.g. "type", or "kind" for a track. */
  field: string;
  /** The value, e.g. "hologram". */
  value: unknown;
};

const valueAt = (document: unknown, path: PropertyKey[]): unknown =>
  path.reduce<unknown>((node, key) => (node as Record<PropertyKey, unknown> | undefined)?.[key], document);

/**
 * Loads `document`, reporting each element with an unknown enum value, and each track of an unknown kind, as skipped.
 * A template from a higher major
 * version throws UnsupportedVersionError (a lower one too, unless `migrations` can upgrade it); anything else invalid
 * throws a ZodError, and unknown fields and values survive.
 */
export function readTemplate(
  input: unknown,
  options: { migrations?: Record<number, Migration> } = {},
): { template: ReaderTemplate; skipped: Skipped[] } {
  // A higher major may not match these types at all, so check the version before reading anything else.
  const document =
    input && typeof input === "object" && !Array.isArray(input)
      ? migrateToSupportedVersion(SCHEMA_VERSION, input as Record<string, unknown>, options.migrations)
      : input;
  // The reader schema relaxes only enums, so if it accepts the document every strict failure is an unknown enum value.
  const template = templateReaderSchema.parse(document);
  const strict = templateSchema.safeParse(document);
  const skipped: Skipped[] = strict.success
    ? []
    : strict.error.issues.map((issue) => ({
        path: issue.path.slice(0, -1).map((key) => (typeof key === "symbol" ? String(key) : key)),
        field: String(issue.path[issue.path.length - 1]),
        value: valueAt(document, issue.path),
      }));
  // An unknown track kind passes validation (it is a free string), so look for it here. Listed after the enum values.
  template.tracks.forEach((track, index) => {
    if (!KNOWN_TRACK_KINDS.has(track.kind)) skipped.push({ path: ["tracks", index], field: "kind", value: track.kind });
  });
  return { template, skipped };
}
