"""A validator of the JSON Schema subset `schema.json` uses (the standard library has none):
`type`, `const`, `enum`, `required`, `properties`, `additionalProperties: false`, `items`,
`minItems`, `maxItems`, `minimum`, `maximum`, `minLength`, `maxLength`, `pattern`, `$ref` to `#/$defs/...`,
`oneOf` of objects told apart by a `const` property. A file the editor writes passes it; any JSON
Schema 2020-12 validator gives the same verdict on these keywords."""
import re

import records as R

TYPES = {"object": dict, "array": list, "string": str, "boolean": bool}


def _type_ok(value, kind):
    if kind == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == "null":
        return value is None
    return isinstance(value, TYPES[kind])


def validate(value, schema, root=None, path="$"):
    root = root or schema
    if "$ref" in schema:
        name = schema["$ref"].split("/")[-1]
        return validate(value, root["$defs"][name], root, path)
    if "oneOf" in schema:
        errors = []
        for option in schema["oneOf"]:
            try:
                validate(value, option, root, path)
                return
            except R.Refused as e:
                errors.append(e.detail)
        raise R.Refused("export: schema", f"{path}: no form matches ({errors[0]})")
    kind = schema.get("type")
    if kind is not None:
        kinds = kind if isinstance(kind, list) else [kind]
        if not any(_type_ok(value, k) for k in kinds):
            raise R.Refused("export: schema", f"{path}: not {kind}")
    if "const" in schema and value != schema["const"]:
        raise R.Refused("export: schema", f"{path}: not {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        raise R.Refused("export: schema", f"{path}: {value!r} not in {schema['enum']}")
    if isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise R.Refused("export: schema", f"{path}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            raise R.Refused("export: schema", f"{path}: above {schema['maximum']}")
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            raise R.Refused("export: schema", f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            raise R.Refused("export: schema", f"{path}: longer than {schema['maxLength']}")
        if "pattern" in schema and not re.fullmatch(schema["pattern"], value):
            raise R.Refused("export: schema", f"{path}: does not match {schema['pattern']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                raise R.Refused("export: schema", f"{path}: {key} missing")
        props = schema.get("properties", {})
        for key, item in value.items():
            if key in props:
                validate(item, props[key], root, f"{path}.{key}")
            elif schema.get("additionalProperties") is False:
                raise R.Refused("export: schema", f"{path}: unknown key {key}")
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            raise R.Refused("export: schema", f"{path}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise R.Refused("export: schema", f"{path}: more than {schema['maxItems']} items")
        if "items" in schema:
            for i, item in enumerate(value):
                validate(item, schema["items"], root, f"{path}[{i}]")
