#!/usr/bin/env python3
"""Exercise cross-package lifecycle for named DROPINS sets."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed: {command}\n{result.stdout}\n{result.stderr}")
    return result


def test_dropin_manage() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-dropin-manage-") as tmp:
        temporary = Path(tmp)
        host = temporary / "host"
        fragments = host / "etc" / "servers"
        source = temporary / "server.json"
        (host / "bin").mkdir(parents=True)
        (host / "etc").mkdir(exist_ok=True)
        rendered = (ROOT / "files" / "dropin-manage.ts").read_text(encoding="utf-8")
        manager = host / "bin" / "dropin-manage.ts"
        manager.write_text(rendered.replace("{{DIR}}", str(host)), encoding="utf-8")
        manager.chmod(0o770)
        (host / "etc" / "config.spec.json").write_text(json.dumps({
            "dropins": {"servers": {"path": str(fragments), "include": "*.json", "disabled_suffix": ".disabled"}}
        }), encoding="utf-8")
        config = host / "bin" / "config.sh"
        config.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        config.chmod(0o770)

        source.write_text('{"version": 1}\n', encoding="utf-8")
        run([str(manager), "put", "servers", str(source), "example.json"])
        active = fragments / "example.json"
        assert active.read_text(encoding="utf-8") == '{"version": 1}\n'

        disabled = fragments / "example.json.disabled"
        active.rename(disabled)
        source.write_text('{"version": 2}\n', encoding="utf-8")
        run([str(manager), "put", "servers", str(source), "example.json"])
        assert not active.exists()
        assert disabled.read_text(encoding="utf-8") == '{"version": 2}\n'

        config.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        source.write_text('{"version": 3}\n', encoding="utf-8")
        failed = run([str(manager), "put", "servers", str(source), "example.json"], check=False)
        assert failed.returncode == 1
        assert disabled.read_text(encoding="utf-8") == '{"version": 2}\n'

        config.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        run([str(manager), "remove", "servers", "example.json"])
        assert not disabled.exists()


if __name__ == "__main__":
    test_dropin_manage()
    print("ok: named drop-in lifecycle")
