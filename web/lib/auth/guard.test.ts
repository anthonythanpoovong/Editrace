import { describe, expect, test } from "vitest";
import { isPublicPath, loginRedirect } from "./guard";

describe("isPublicPath", () => {
  test.each(["/", "/login", "/signup", "/forgot-password", "/auth/callback", "/api/waitlist"])("%s is public", (p) => expect(isPublicPath(p)).toBe(true));
  test.each(["/account", "/reset-password", "/upload", "/authx", "/login/extra", "/api/waitlist/extra", "/api/runtime"])("%s needs a session", (p) => expect(isPublicPath(p)).toBe(false));
});

describe("loginRedirect", () => {
  test("keeps the page and its query string", () => expect(loginRedirect("/upload", "?id=1")).toBe("/login?next=%2Fupload%3Fid%3D1"));
  test("never carries an off-site target", () => expect(loginRedirect("//evil.example", "")).toBe("/login?next=%2F"));
});
