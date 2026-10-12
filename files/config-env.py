#!/usr/bin/env python3
"""Literal ENV assignment reduction and consumer-specific serialization."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import sys


NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def literal(value: str, label: str) -> str:
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ValueError(f"{label}: control characters/multiline values are not supported")
    return value


def assignments(text: str, label: str) -> dict[str, str]:
    result = {}
    for number, line in enumerate(text.splitlines(), 1):
        row = line.strip()
        if not row or row.startswith("#"):
            continue
        key, separator, raw = row.partition("=")
        if not separator or not NAME.fullmatch(key):
            raise ValueError(f"{label}:{number}: expected NAME=literal assignment")
        # JSON double-quoted strings give a precise literal grammar. Single
        # quotes are also literal (no escapes). Unquoted values have no whitespace.
        if raw.startswith('"'):
            value = json.loads(raw)
            if not isinstance(value, str):
                raise ValueError(f"{label}:{number}: value must be a string")
        elif raw.startswith("'"):
            if not raw.endswith("'") or "'" in raw[1:-1]:
                raise ValueError(f"{label}:{number}: malformed single-quoted literal")
            value = raw[1:-1]
        else:
            if any(char.isspace() for char in raw) or any(char in raw for char in "'\"\\"):
                raise ValueError(f"{label}:{number}: quote this value as a JSON string")
            value = raw
        result[key] = literal(value, f"{label}:{number}")
    return result


def serialize(values: dict[str, str], projection: str) -> str:
    lines = []
    for key, value in values.items():
        if projection == "env":
            # systemd EnvironmentFile does not expand dollars/backticks. Its
            # double-quote escape rules differ from shell and JSON.
            escaped = value.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'{key}="{escaped}"')
        elif projection == "env-export":
            lines.append(f"export {key}={shlex.quote(value)}")
        elif projection == "env-zsh":
            # An explicitly empty value is an override, not an unset default.
            lines.append(f"if (( ! ${{+{key}}} )); then export {key}={shlex.quote(value)}; fi")
        else:
            raise ValueError(f"unknown ENV projection: {projection}")
    return "\n".join(lines) + ("\n" if lines else "")


def main() -> None:
    projection = sys.argv[1]
    values = {}
    for line in Path(os.environ["CONFIG_INPUTS_FILE"]).read_text().splitlines():
        _kind, identity, path, _settings = line.split("\t", 3)
        values.update(assignments(Path(path).read_text(), identity))
    Path(os.environ["CONFIG_CANDIDATE"]).write_text(serialize(values, projection))


if __name__ == "__main__":
    main()
