import { describe, expect, it } from "vitest";
import { probe, probe2 } from "./probe";

describe("probe", () => {
  it("doubles above 10 and adds one otherwise", () => {
    expect(probe(11)).toBe(22);
    expect(probe(1)).toBe(2);
  });
  it("subtracts one", () => {
    expect(probe2(5)).toBe(4);
  });
});
