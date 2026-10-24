import { expect, test } from "vitest";
import { isPublicPath } from "../../../lib/auth/guard";
import { GET } from "./route";

test("reports the running Node version", async () => {
  expect(await GET().json()).toEqual({ node: process.version });
});
test("is behind sign-in", () => {
  expect(isPublicPath("/api/runtime")).toBe(false);
});
