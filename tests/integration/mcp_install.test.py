#!/usr/bin/env python3
"""Exercise the thin MCP adapter over generic DROPINS lifecycle."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}\n{result.stderr}"
        )
    return result


def test_mcp_install() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-mcp-install-") as tmp:
        temporary = Path(tmp)
        host = temporary / "host"
        source = temporary / "example-git"
        target = host / "etc" / "mcp"
        (host / "bin").mkdir(parents=True)
        (source / "etc").mkdir(parents=True)

        rendered = (ROOT / "files" / "mcp-dropin.ts").read_text(encoding="utf-8")
        adapter = host / "bin" / "mcp-dropin.ts"
        adapter.write_text(rendered.replace("{{DIR}}", str(host)), encoding="utf-8")
        adapter.chmod(0o770)
        manager_rendered = (ROOT / "files" / "dropin-manage.ts").read_text(encoding="utf-8")
        manager = host / "bin" / "dropin-manage.ts"
        manager.write_text(manager_rendered.replace("{{DIR}}", str(host)), encoding="utf-8")
        manager.chmod(0o770)
        (host / "etc").mkdir(exist_ok=True)
        (host / "etc" / "config.spec.json").write_text(
            json.dumps({"dropins": {"amp-mcp": {"path": str(target), "include": "*.json", "disabled_suffix": ".disabled"}}}),
            encoding="utf-8",
        )
        (host / "bin" / "config.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (host / "bin" / "config.sh").chmod(0o770)
        (source / "etc" / "mcp.json").write_text(
            json.dumps({"type": "remote", "url": "https://example.test/mcp"}),
            encoding="utf-8",
        )

        run([str(adapter), "amp-mcp", "amp.mcpServers", "true", str(source)])
        fragment = target / "example.json"
        assert json.loads(fragment.read_text(encoding="utf-8")) == {
            "amp": {
                "mcpServers": {
                    "example": {
                        "type": "remote",
                        "url": "https://example.test/mcp",
                        "enabled": True,
                    }
                }
            }
        }

        disabled = fragment.with_suffix(".json.disabled")
        fragment.rename(disabled)
        (source / "etc" / "mcp.json").write_text(
            json.dumps({"type": "remote", "url": "https://example.test/new"}), encoding="utf-8"
        )
        reinstall = run([str(adapter), "amp-mcp", "amp.mcpServers", "true", str(source)], check=False)
        assert reinstall.returncode == 0
        assert not fragment.exists()
        assert "https://example.test/new" in disabled.read_text(encoding="utf-8")


if __name__ == "__main__":
    test_mcp_install()
    print("ok: MCP drop-in adapter integration")
