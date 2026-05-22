/** 结构化日志级别 */
export type LogLevel = "info" | "warn" | "error";

/** 网关日志接口：每条记录为 JSON 行，含 event 与可选 details */
export type Logger = {
  info: (event: string, details?: Record<string, unknown>) => void;
  warn: (event: string, details?: Record<string, unknown>) => void;
  error: (event: string, details?: Record<string, unknown>) => void;
};

type LoggerOptions = {
  /** 是否在 details 中脱敏敏感字符串 */
  redactSecrets: boolean;
  /** 需要替换为 [REDACTED] 的明文列表（如 authToken） */
  secrets: string[];
  /** 自定义输出；默认写入 stderr */
  write?: (line: string) => void;
};

/** 创建 JSON 行日志器，便于桌面端或脚本解析 */
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

/** 递归遍历对象/数组，对字符串字段做密钥脱敏 */
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
