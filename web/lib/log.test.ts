import { expect, test } from "vitest";
import { createLogger, type LogLevel } from "./log";

function capture() {
  const lines: { entry: Record<string, unknown>; level: LogLevel }[] = [];
  const write = (line: string, level: LogLevel) =>
    lines.push({ entry: JSON.parse(line), level });
  return { lines, write };
}

test("writes one JSON object with the standard fields", () => {
  const { lines, write } = capture();
  createLogger("web", {}, write).info("job started", { duration_ms: 5 });

  expect(lines).toHaveLength(1);
  const { entry, level } = lines[0];
  expect(level).toBe("info");
  expect(entry).toMatchObject({
    level: "info",
    service: "web",
    msg: "job started",
    duration_ms: 5,
  });
  expect(typeof entry.env).toBe("string");
  expect(new Date(entry.ts as string).toISOString()).toBe(entry.ts);
});

test("child loggers carry context on every line", () => {
  const { lines, write } = capture();
  const log = createLogger("web", { request_id: "r1" }, write).child({
    job_id: "j1",
    user_id: "u1",
  });
  log.info("a");
  log.warn("b");

  for (const { entry } of lines) {
    expect(entry).toMatchObject({
      request_id: "r1",
      job_id: "j1",
      user_id: "u1",
    });
  }
});

test("redacts sensitive keys, including nested ones", () => {
  const { lines, write } = capture();
  createLogger("web", {}, write).info("call", {
    authorization: "Bearer abc",
    headers: { cookie: "sb=1", accept: "json" },
    user_email: "a@b.com",
    access_token: "xyz",
  });

  const { entry } = lines[0];
  expect(entry.authorization).toBe("[redacted]");
  expect(entry.user_email).toBe("[redacted]");
  expect(entry.access_token).toBe("[redacted]");
  expect(entry.headers).toEqual({ cookie: "[redacted]", accept: "json" });
  expect(JSON.stringify(entry)).not.toContain("abc");
});

test("truncates past the depth limit, so deep secrets are never logged", () => {
  const { lines, write } = capture();
  createLogger("web", {}, write).info("deep", {
    a: { b: { c: { d: { e: { f: { token: "x" } } } } } },
  });

  const { entry } = lines[0];
  expect(JSON.stringify(entry)).not.toContain('"x"');
  expect(JSON.stringify(entry)).toContain("[truncated]");
});

test("does not throw on circular objects", () => {
  const { lines, write } = capture();
  const loop: Record<string, unknown> = { name: "loop" };
  loop.self = loop;

  expect(() =>
    createLogger("web", {}, write).info("circular", { loop }),
  ).not.toThrow();
  expect(lines[0].entry.msg).toBe("circular");
});

test("keeps the line when fields can't be serialized", () => {
  const { lines, write } = capture();
  createLogger("web", { job_id: "j1" }, write).error("job failed", {
    size: BigInt(1),
  });

  const { entry, level } = lines[0];
  expect(level).toBe("error");
  expect(entry).toMatchObject({ msg: "job failed", service: "web" });
  expect(entry.log_error).toContain("fields not serializable");
});

test("keeps dates, URLs, maps and sets instead of logging {}", () => {
  const { lines, write } = capture();
  createLogger("web", {}, write).info("job started", {
    started_at: new Date("2026-10-12T19:38:35.000Z"),
    source: new URL("https://example.com/a?b=1"),
    by_detector: new Map([["cuts", 3]]),
    tags: new Set(["a", "b"]),
  });

  const { entry } = lines[0];
  expect(entry.started_at).toBe("2026-10-12T19:38:35.000Z");
  expect(entry.source).toBe("https://example.com/a?b=1");
  expect(entry.by_detector).toEqual({ cuts: 3 });
  expect(entry.tags).toEqual(["a", "b"]);
});

test("fields can't overwrite the standard fields", () => {
  const { lines, write } = capture();
  createLogger("web", { service: "spoofed" }, write).warn("real message", {
    level: "debug",
    msg: "fake message",
    ts: "yesterday",
  });

  const { entry, level } = lines[0];
  expect(level).toBe("warn");
  expect(entry).toMatchObject({
    level: "warn",
    msg: "real message",
    service: "web",
  });
  expect(entry.ts).not.toBe("yesterday");
});

test("keeps token counts but still redacts tokens", () => {
  const { lines, write } = capture();
  createLogger("web", {}, write).info("assistant reply", {
    usage: {
      input_tokens: 512,
      output_tokens: 128,
      cache_read_input_tokens: 64,
    },
    max_tokens: 1024,
    token_count: 7,
    access_token: "abc",
    auth_tokens: ["abc", "def"],
    refresh_token: 12345,
  });

  const { entry } = lines[0];
  expect(entry.usage).toEqual({
    input_tokens: 512,
    output_tokens: 128,
    cache_read_input_tokens: 64,
  });
  expect(entry.max_tokens).toBe(1024);
  expect(entry.token_count).toBe(7);
  expect(entry.access_token).toBe("[redacted]");
  expect(entry.auth_tokens).toBe("[redacted]");
  expect(entry.refresh_token).toBe("[redacted]");
});

test("serializes errors", () => {
  const { lines, write } = capture();
  createLogger("web", {}, write).error("job failed", {
    err: new TypeError("boom"),
  });

  const { entry, level } = lines[0];
  expect(level).toBe("error");
  expect(entry.err).toMatchObject({ name: "TypeError", message: "boom" });
  expect((entry.err as { stack: string }).stack).toContain("boom");
});
