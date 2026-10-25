// Structured JSON logger. Field names and rules: docs/observability.md

export type LogLevel = "debug" | "info" | "warn" | "error";

export type LogContext = {
  request_id?: string;
  job_id?: string;
  template_id?: string;
  user_id?: string;
  [key: string]: unknown;
};

export type Logger = {
  debug: (msg: string, fields?: Record<string, unknown>) => void;
  info: (msg: string, fields?: Record<string, unknown>) => void;
  warn: (msg: string, fields?: Record<string, unknown>) => void;
  error: (msg: string, fields?: Record<string, unknown>) => void;
  child: (context: LogContext) => Logger;
};

const SENSITIVE = /token|authorization|password|secret|api_?key|cookie|email/i;
// LLM usage counts (input_tokens, max_tokens, token_count): kept when the value is a number.
const COUNT_KEY = /tokens$|token_count$/i;

function isSensitive(key: string, value: unknown): boolean {
  if (!SENSITIVE.test(key)) return false;
  return !(COUNT_KEY.test(key) && typeof value === "number");
}

function serializeError(err: Error): Record<string, unknown> {
  return { name: err.name, message: err.message, stack: err.stack };
}

const MAX_DEPTH = 5;

function clean(value: unknown, depth = 0): unknown {
  if (value instanceof Error) return serializeError(value);
  if (value === null || typeof value !== "object") return value;
  // Past the limit, drop the value: returning it raw would skip redaction and keep cycles.
  if (depth > MAX_DEPTH) return "[truncated]";
  // Date, URL and others serialize through toJSON; Object.entries would turn them into {}.
  const { toJSON } = value as { toJSON?: unknown };
  if (typeof toJSON === "function") return clean(toJSON.call(value), depth + 1);
  if (value instanceof Map) return clean(Object.fromEntries(value), depth);
  if (value instanceof Set) return clean([...value], depth);
  if (Array.isArray(value)) return value.map((v) => clean(v, depth + 1));
  return Object.fromEntries(
    Object.entries(value).map(([k, v]) => [
      k,
      isSensitive(k, v) ? "[redacted]" : clean(v, depth + 1),
    ]),
  );
}

// Fields can't overwrite ts, level, service, env or msg: a stray `level` would break filtering.
function withoutReserved(
  fields: Record<string, unknown>,
  base: Record<string, unknown>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(fields).filter(([k]) => !(k in base)),
  );
}

export function createLogger(
  service: string,
  context: LogContext = {},
  write: (line: string, level: LogLevel) => void = defaultWrite,
): Logger {
  const emit = (
    level: LogLevel,
    msg: string,
    fields: Record<string, unknown> = {},
  ) => {
    const base = {
      ts: new Date().toISOString(),
      level,
      service,
      env: process.env.APP_ENV ?? "dev",
      msg,
    };
    let line: string;
    try {
      const cleaned = clean({ ...context, ...fields }) as Record<
        string,
        unknown
      >;
      line = JSON.stringify({ ...base, ...withoutReserved(cleaned, base) });
    } catch (err) {
      // Logging must never throw (e.g. a BigInt field). Keep the line, drop the fields.
      line = JSON.stringify({
        ...base,
        log_error: `fields not serializable: ${err instanceof Error ? err.message : String(err)}`,
      });
    }
    write(line, level);
  };

  return {
    debug: (msg, fields) => emit("debug", msg, fields),
    info: (msg, fields) => emit("info", msg, fields),
    warn: (msg, fields) => emit("warn", msg, fields),
    error: (msg, fields) => emit("error", msg, fields),
    child: (more) => createLogger(service, { ...context, ...more }, write),
  };
}

function defaultWrite(line: string, level: LogLevel) {
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}
