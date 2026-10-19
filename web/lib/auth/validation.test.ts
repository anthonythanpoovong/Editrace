import { describe, expect, test } from "vitest";
import { credentialsSchema, emailSchema, newPasswordSchema, parseForm } from "./validation";

const form = (o: Record<string, string>) => Object.entries(o).reduce((f, [k, v]) => (f.set(k, v), f), new FormData());

describe("parseForm", () => {
  test("trims and lowercases the email", () => {
    expect(parseForm(credentialsSchema, form({ email: "  Ana@Example.COM ", password: "longenough" }))).toEqual({
      ok: true,
      data: { email: "ana@example.com", password: "longenough" },
    });
  });
  test("rejects a bad email", () => expect(parseForm(emailSchema, form({ email: "nope" }))).toEqual({ ok: false, error: "Enter a valid email address." }));
  test("rejects a short password", () =>
    expect(parseForm(credentialsSchema, form({ email: "a@b.co", password: "short" }))).toEqual({ ok: false, error: "Use at least 8 characters." }));
  test("rejects a password over bcrypt's 72 limit", () =>
    expect(parseForm(credentialsSchema, form({ email: "a@b.co", password: "x".repeat(73) }))).toEqual({ ok: false, error: "Use at most 72 characters." }));
  test("rejects mismatched new passwords", () =>
    expect(parseForm(newPasswordSchema, form({ password: "longenough", confirm: "different1" }))).toEqual({ ok: false, error: "The passwords don't match." }));
  test("accepts matching new passwords", () =>
    expect(parseForm(newPasswordSchema, form({ password: "longenough", confirm: "longenough" })).ok).toBe(true));
});
