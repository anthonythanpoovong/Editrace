import { expect, test } from "vitest";
import { secondsToFrame } from "./frames";

test("converts seconds to frames at 30000/1001 fps", () => {
  expect(secondsToFrame(1, 30000, 1001)).toBe(30);
});

test("rejects a non-positive fps", () => {
  expect(() => secondsToFrame(1, 0, 1)).toThrow("fps must be positive");
});
