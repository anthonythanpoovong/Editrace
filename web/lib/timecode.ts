// Frame counts as editor timecodes (HH:MM:SS:FF). Templates store integer frames; this is only for display.
// Drop-frame rates (29.97, 59.94) skip frame numbers 0–1 (0–3 at 59.94) at the start of every minute except
// every tenth, so the timecode keeps up with the clock. They're shown with a ";" before the frames.

const pad = (n: number) => String(n).padStart(2, "0");

export function framesToTimecode(frames: number, fps: number): string {
  if (!Number.isInteger(frames) || frames < 0) {
    throw new RangeError(`frames must be a non-negative integer, got ${frames}`);
  }
  if (!(fps > 0)) throw new RangeError(`fps must be positive, got ${fps}`);
  const nominal = Math.round(fps);
  const dropFrame = fps === 29.97 || fps === 59.94;
  let f = frames;
  if (dropFrame) {
    const drop = nominal / 15;
    const perMinute = nominal * 60 - drop;
    const perTenMinutes = perMinute * 10 + drop;
    const tens = Math.floor(f / perTenMinutes);
    const rest = f % perTenMinutes;
    f += drop * 9 * tens + (rest > drop ? drop * Math.floor((rest - drop) / perMinute) : 0);
  }
  const ff = f % nominal;
  const seconds = Math.floor(f / nominal);
  const h = Math.floor(seconds / 3600);
  const m = Math.floor(seconds / 60) % 60;
  const s = seconds % 60;
  return `${pad(h)}:${pad(m)}:${pad(s)}${dropFrame ? ";" : ":"}${pad(ff)}`;
}
