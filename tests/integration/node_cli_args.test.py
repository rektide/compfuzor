#!/usr/bin/env python3
"""Focused contracts for the CONFIG, LINKS, and Zim node:util parsers."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def evaluate(module: Path, expression: str) -> subprocess.CompletedProcess[str]:
    script = f"import * as cli from {json.dumps(module.as_uri())}; console.log(JSON.stringify({expression}))"
    return subprocess.run(
        ["node", "--input-type=module", "--eval", script],
        cwd=ROOT,
        check=False,
        text=True,
        capture_output=True,
    )


def parsed(module: Path, expression: str) -> dict:
    result = evaluate(module, expression)
    if result.returncode:
        raise AssertionError(f"parser failed ({result.returncode})\n{result.stdout}\n{result.stderr}")
    return json.loads(result.stdout)


def test_config_parser() -> None:
    module = ROOT / "files" / "config" / "cli.ts"
    options = parsed(
        module,
        "cli.parseConfigCommandArgs(['--context=user', '--strategy', 'copy', 'alpha', 'beta', '--json-array'], '/opt/example', 'config-status.sh')",
    )
    assert options["context"] == "user"
    assert options["strategy"] == "copy"
    assert options["format"] == "array"
    assert options["args"] == ["alpha", "beta"]
    assert options["specPath"] == "/opt/example/etc/config.spec.json"
    unknown = evaluate(module, "cli.parseConfigCommandArgs(['--hostile'], '/opt/example', 'config-status.sh')")
    assert unknown.returncode != 0 and "Unknown option '--hostile'" in unknown.stderr


def test_zim_parser() -> None:
    module = ROOT / "files" / "zim" / "install.ts"
    options = parsed(
        module,
        "cli.parseZimArgs(['import', '--context=user', '/producer', '--dropins=copy'], '/opt/zim-main')",
    )
    assert options["action"] == "import"
    assert options["context"] == "user"
    assert options["dropins"] == "copy"
    assert options["args"] == ["/producer"]
    unknown = evaluate(module, "cli.parseZimArgs(['status', '--hostile'], '/opt/zim-main')")
    assert unknown.returncode != 0 and "Unknown option '--hostile'" in unknown.stderr


def test_links_parser() -> None:
    module = ROOT / "files" / "links" / "cli.ts"
    options = parsed(
        module,
        "cli.parseLinksArgs(['apply', '--scope=user', '--id', 'one,two', '--id=three', '-qq', '--sudo', '/plan.json'], '/default.json')",
    )
    assert options["command"] == "apply"
    assert options["scope"] == "user"
    assert options["id"] == ["one", "two", "three"]
    assert options["quiet"] == 2
    assert options["sudo"] == "always"
    assert options["paths"] == ["/plan.json"]
    explicit = parsed(module, "cli.parseLinksArgs(['apply', '--sudo=never'], '/default.json')")
    assert explicit["sudo"] == "never" and explicit["paths"] == ["/default.json"]
    unknown = evaluate(module, "cli.parseLinksArgs(['status', '--hostile'], '/default.json')")
    assert unknown.returncode != 0 and "Unknown option '--hostile'" in unknown.stderr


if __name__ == "__main__":
    test_config_parser()
    test_zim_parser()
    test_links_parser()
    print("ok: Node CLI parseArgs contracts")
