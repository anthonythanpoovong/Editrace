import { describe, expect, it } from "vitest";
import { framesToTimecode } from "./timecode";

describe("framesToTimecode", () => {
  it("formats whole-frame rates", () => {
    expect(framesToTimecode(0, 24)).toBe("00:00:00:00");
    expect(framesToTimecode(23, 24)).toBe("00:00:00:23");
    expect(framesToTimecode(24 * 3661 + 5, 24)).toBe("01:01:01:05");
    expect(framesToTimecode(25 * 60, 25)).toBe("00:01:00:00");
  });

  it("rejects fractional or negative frames and a zero rate", () => {
    expect(() => framesToTimecode(1.5, 24)).toThrow(RangeError);
    expect(() => framesToTimecode(-1, 24)).toThrow(RangeError);
    expect(() => framesToTimecode(10, 0)).toThrow(RangeError);
  });
});
