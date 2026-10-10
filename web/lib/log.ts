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

function serializeError(err: Error): Record<string, unknown> {
  return { name: err.name, message: err.message, stack: err.stack };
}

const MAX_DEPTH = 5;

function clean(value: unknown, depth = 0): unknown {
  if (value instanceof Error) return serializeError(value);
  if (value === null || typeof value !== "object") return value;
  // Past the limit, drop the value: returning it raw would skip redaction and keep cycles.
  if (depth > MAX_DEPTH) return "[truncated]";
  if (Array.isArray(value)) return value.map((v) => clean(v, depth + 1));
  return Object.fromEntries(
    Object.entries(value).map(([k, v]) => [
      k,
      SENSITIVE.test(k) ? "[redacted]" : clean(v, depth + 1),
    ]),
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
      line = JSON.stringify({
        ...base,
        ...(clean({ ...context, ...fields }) as Record<string, unknown>),
      });
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
