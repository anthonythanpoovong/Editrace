// Reading a template that may come from a newer minor version (#206). The TypeScript counterpart of
// editrace_schema/reader.py: the strict `templateSchema` is for writers and rejects an unknown enum value, but
// docs/schema.md says a reader treats one as unsupported ("skipped") and never fails the whole template.
import { templateReaderSchema } from "./generated/template.reader.zod";
import { templateSchema } from "./generated/template.zod";

export type ReaderTemplate = ReturnType<typeof templateReaderSchema.parse>;

/** An element holding an enum value this version of the schema doesn't know. */
export type Skipped = {
  /** Where the element is, e.g. ["tracks", 0, "transitions", 1]. */
  path: (string | number)[];
  /** The field with the unknown value, e.g. "type". */
  field: string;
  /** The value, e.g. "hologram". */
  value: unknown;
};

const valueAt = (document: unknown, path: PropertyKey[]): unknown =>
  path.reduce<unknown>((node, key) => (node as Record<PropertyKey, unknown> | undefined)?.[key], document);

/**
 * Loads `document`, reporting each element with an unknown enum value as skipped. Anything else invalid throws a
 * ZodError, and unknown fields and values survive.
 */
export function readTemplate(document: unknown): { template: ReaderTemplate; skipped: Skipped[] } {
  // The reader schema relaxes only enums, so if it accepts the document every strict failure is an unknown enum value.
  const template = templateReaderSchema.parse(document);
  const strict = templateSchema.safeParse(document);
  if (strict.success) return { template, skipped: [] };
  const skipped = strict.error.issues.map((issue) => ({
    path: issue.path.slice(0, -1).map((key) => (typeof key === "symbol" ? String(key) : key)),
    field: String(issue.path[issue.path.length - 1]),
    value: valueAt(document, issue.path),
  }));
  return { template, skipped };
}
