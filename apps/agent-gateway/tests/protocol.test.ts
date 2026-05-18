import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

const protocolRoot = path.resolve(process.cwd(), "..", "..", "packages", "protocol");
const require = createRequire(import.meta.url);

type AjvLike = {
  compile: (schema: unknown) => ValidateFunction;
  errorsText: (errors?: unknown) => string;
};
type ValidateFunction = {
  (data: unknown): boolean;
  errors?: unknown;
};
type AjvConstructor = new (options: { allErrors: boolean }) => AjvLike;
type FormatsPlugin = (ajv: AjvLike) => void;

const ajv2020Module = require("ajv/dist/2020") as { default?: AjvConstructor } & AjvConstructor;
const addFormatsModule = require("ajv-formats") as { default?: FormatsPlugin } & FormatsPlugin;
const Ajv2020 = ajv2020Module.default ?? ajv2020Module;
const addFormats = addFormatsModule.default ?? addFormatsModule;

test("protocol examples validate against their JSON schemas", () => {
  const examples = [
    {
      schema: "schemas/event.schema.json",
      example: "examples/text-delta.event.json"
    },
    {
      schema: "schemas/event.schema.json",
      example: "examples/permission-request.event.json"
    },
    {
      schema: "schemas/event.schema.json",
      example: "examples/question-request.event.json"
    },
    {
      schema: "schemas/error.schema.json",
      example: "examples/error.unauthorized.json"
    },
    {
      schema: "schemas/health.schema.json",
      example: "examples/health.ok.json"
    }
  ];

  for (const item of examples) {
    const ajv = new Ajv2020({ allErrors: true });
    addFormats(ajv);
    const schema = readProtocolJson(item.schema);
    const example = readProtocolJson(item.example);
    const validate = ajv.compile(schema);

    assert.equal(
      validate(example),
      true,
      `${item.example} failed validation: ${ajv.errorsText(validate.errors)}`
    );
  }
});

function readProtocolJson(relativePath: string): unknown {
  return JSON.parse(
    fs.readFileSync(path.join(protocolRoot, relativePath), "utf8")
  ) as unknown;
}
