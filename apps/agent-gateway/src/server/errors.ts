import type { ServerResponse } from "node:http";

import type { ErrorResponse } from "../protocol/types.js";

export function createErrorResponse(
  code: string,
  message: string,
  details: Record<string, unknown> = {}
): ErrorResponse {
  return {
    error: {
      code,
      message,
      details
    }
  };
}

export function writeJson(
  response: ServerResponse,
  statusCode: number,
  payload: unknown
): void {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body)
  });
  response.end(body);
}

export function writeError(
  response: ServerResponse,
  statusCode: number,
  code: string,
  message: string,
  details: Record<string, unknown> = {}
): void {
  writeJson(response, statusCode, createErrorResponse(code, message, details));
}
