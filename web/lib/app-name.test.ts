import { expect, test } from "vitest";
import { appName } from "./app-name";

test("app name is Editrace", () => {
  expect(appName).toBe("Editrace");
});
