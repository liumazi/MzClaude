export type LogLevel = "info" | "warn" | "error";

export type Logger = {
  info: (event: string, details?: Record<string, unknown>) => void;
  warn: (event: string, details?: Record<string, unknown>) => void;
  error: (event: string, details?: Record<string, unknown>) => void;
};

type LoggerOptions = {
  redactSecrets: boolean;
  secrets: string[];
  write?: (line: string) => void;
};

export function createLogger(options: LoggerOptions): Logger {
  const write = options.write ?? ((line: string) => process.stderr.write(`${line}\n`));

  function log(level: LogLevel, event: string, details: Record<string, unknown> = {}): void {
    write(JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      event,
      details: redactValue(details, options) as Record<string, unknown>
    }));
  }

  return {
    info: (event, details) => log("info", event, details),
    warn: (event, details) => log("warn", event, details),
    error: (event, details) => log("error", event, details)
  };
}

function redactValue(value: unknown, options: LoggerOptions): unknown {
  if (!options.redactSecrets) {
    return value;
  }

  if (typeof value === "string") {
    return options.secrets.reduce(
      (current, secret) => secret ? current.replaceAll(secret, "[REDACTED]") : current,
      value
    );
  }

  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item, options));
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, redactValue(nested, options)])
    );
  }

  return value;
}
