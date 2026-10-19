import { describe, expect, test } from "vitest";
import { getOrigin, safeNext } from "./redirect";

describe("safeNext", () => {
  test.each([
    ["/account", "/account"],
    ["/upload?id=1#top", "/upload?id=1#top"],
  ])("keeps the site path %s", (input, expected) => expect(safeNext(input)).toBe(expected));

  test.each([
    "https://evil.example",
    "//evil.example",
    "/\\evil.example",
    "javascript:alert(1)",
    "account",
    "",
    null,
    undefined,
    42,
  ])("falls back for %j", (input) => expect(safeNext(input, "/home")).toBe("/home"));

  test("falls back for a tab that the URL parser would strip into //", () => {
    expect(safeNext("/\t/evil.example", "/home")).toBe("/home");
  });
});

describe("getOrigin", () => {
  const h = (init: Record<string, string>) => new Headers(init);
  test("prefers the Origin header", () => expect(getOrigin(h({ origin: "https://a.example", host: "b" }))).toBe("https://a.example"));
  test("builds from forwarded headers behind a proxy", () =>
    expect(getOrigin(h({ "x-forwarded-host": "app.example", "x-forwarded-proto": "https", host: "internal" }))).toBe("https://app.example"));
  test("uses http for localhost", () => expect(getOrigin(h({ host: "localhost:3000" }))).toBe("http://localhost:3000"));
  test("uses http for 127.0.0.1", () => expect(getOrigin(h({ host: "127.0.0.1:3000" }))).toBe("http://127.0.0.1:3000"));
  test("uses https for other hosts", () => expect(getOrigin(h({ host: "app.example" }))).toBe("https://app.example"));
  test("defaults to localhost with no host", () => expect(getOrigin(h({}))).toBe("http://localhost:3000"));
});
