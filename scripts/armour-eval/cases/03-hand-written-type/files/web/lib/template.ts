// The template shape the breakdown page renders.

export interface Rational {
  num: number;
  den: number;
}

export interface FrameRange {
  start: number;
  duration: number;
}

export interface Slot {
  id: string;
  range: FrameRange;
  speed?: Rational;
  confidence: number;
}

export interface Cut {
  id: string;
  frame: number;
  confidence: number;
}

export interface Track {
  id: string;
  kind: "video" | "text" | "captions";
  slots?: Slot[];
  cuts?: Cut[];
}

export interface Template {
  schema_version: string;
  source: {
    duration: number;
    fps: Rational;
    resolution: { width: number; height: number };
  };
  tracks: Track[];
}

export function slotCount(template: Template): number {
  return template.tracks.reduce((n, track) => n + (track.slots?.length ?? 0), 0);
}
