// Converts a time in seconds to a whole frame number at a rational frame rate (num/den fps).
export function secondsToFrame(seconds: number, fpsNum: number, fpsDen: number): number {
  if (fpsNum <= 0 || fpsDen <= 0) {
    throw new Error("fps must be positive");
  }
  return Math.round((seconds * fpsNum) / fpsDen);
}
