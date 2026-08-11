#!/usr/bin/env python3
"""Exercise MCP fragment installation for nested wrappers and disabled state."""

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

        rendered = (ROOT / "files" / "mcp-install.ts").read_text(encoding="utf-8")
        installer = host / "bin" / "mcp-install.ts"
        installer.write_text(rendered.replace("{{DIR}}", str(host)), encoding="utf-8")
        installer.chmod(0o770)
        (host / "env.export").write_text(
            f'export MCP_TARGET="{target}"\nexport MCP_WRAPPER="amp.mcpServers"\n',
            encoding="utf-8",
        )
        (host / "bin" / "config.sh").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (host / "bin" / "config.sh").chmod(0o770)
        (source / "etc" / "mcp.json").write_text(
            json.dumps({"type": "remote", "url": "https://example.test/mcp"}),
            encoding="utf-8",
        )

        run([str(installer), str(source)])
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
        reinstall = run([str(installer), str(source)], check=False)
        assert reinstall.returncode == 1
        assert str(disabled) in reinstall.stderr
        assert not fragment.exists()


if __name__ == "__main__":
    test_mcp_install()
    print("ok: MCP installer integration")
