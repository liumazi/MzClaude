/**
 * 读取并解析 HTTP JSON 请求体，限制最大 1MB，防止大包拖垮网关。
 */
import type { IncomingMessage } from "node:http";

const MAX_JSON_BODY_BYTES = 1024 * 1024;

export async function readJsonBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let totalLength = 0;

  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    totalLength += buffer.length;
    if (totalLength > MAX_JSON_BODY_BYTES) {
      throw new BodyReadError("request_too_large", "Request body is too large.");
    }
    chunks.push(buffer);
  }

  const text = Buffer.concat(chunks).toString("utf8");
  if (!text.trim()) {
    throw new BodyReadError("invalid_json", "Request body must be a JSON object.");
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new BodyReadError("invalid_json", "Request body must be valid JSON.");
  }
}

/** 请求体读取/解析失败时抛出，由 server 映射为 400 */
export class BodyReadError extends Error {
  constructor(
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}
