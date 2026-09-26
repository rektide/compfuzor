#!/usr/bin/env python3
"""MCP producers emit only portable records; JSON placement is a CONFIG input."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_mcp_records() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-mcp-records-") as tmp:
        temporary = Path(tmp)
        playbook = temporary / "render.pb"
        result_file = temporary / "result.json"
        def render(variables: str) -> list[dict]:
            playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: docs-mcp
    ETC_FILES: []
{variables}
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/gen_mcp.tasks')!r}
    - ansible.builtin.copy:
        dest: {str(result_file)!r}
        content: "{{{{ ETC_FILES | to_json }}}}"
""", encoding="utf-8")
            result = subprocess.run(
                ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
                cwd=ROOT,
                env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, f"{result.stdout}\n{result.stderr}"
            return json.loads(result_file.read_text())

        assert render("    MCP_COMMAND: [docs-mcp, stdio]\n    MCP_ENV: [DOCS_API_KEY]") == [{
            "name": "mcp.json",
            "json": {
                "type": "local", "command": ["docs-mcp", "stdio"],
                "environment": {"DOCS_API_KEY": "${DOCS_API_KEY}"},
            },
        }]
        assert render("    MCP_COMMAND: [docs-mcp, stdio]") == [{
            "name": "mcp.json", "json": {"type": "local", "command": ["docs-mcp", "stdio"]},
        }]
        assert render("    MCP_URL: https://example.test/mcp") == [{
            "name": "mcp.json", "json": {"type": "remote", "url": "https://example.test/mcp"},
        }]


if __name__ == "__main__":
    test_mcp_records()
    print("ok: portable MCP producer record")
