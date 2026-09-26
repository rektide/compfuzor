#!/usr/bin/env python3
"""Exercise durable MCP transformation over consumer remote lifecycle."""

from __future__ import annotations

import json
import os
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

        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook = temporary / "render.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: mcp-test
    DIR: {str(host)!r}
    BINS_DIR: {str(host / 'bin')!r}
    BINMODE: '0755'
    BINS: []
    MCP_CLIENT:
      remote: amp-mcp
      wrapper: amp.mcpServers
      command_args: true
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/gen_mcp.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/bins.tasks')!r}
""",
            encoding="utf-8",
        )
        result = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
            env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"{result.stdout}\n{result.stderr}"
        adapter = host / "bin" / "mcp-dropin.ts"
        core = host / "bin" / "mcp-dropin-core.ts"
        assert adapter.read_text(encoding="utf-8").startswith("#!/usr/bin/env node\nimport { run }")
        assert core.read_text(encoding="utf-8").startswith("#!/usr/bin/env node\n/** Transform")
        assert "{{DIR}}" not in core.read_text(encoding="utf-8")
        assert "#!/bin/bash" not in adapter.read_text(encoding="utf-8")
        manager_rendered = (ROOT / "build" / "runtime" / "compfuzor-runtime.mjs").read_text(encoding="utf-8")
        manager = host / "bin" / "config-remote.mjs"
        manager.write_text(manager_rendered.replace("{{DIR}}", str(host)), encoding="utf-8")
        manager.chmod(0o770)
        (host / "etc").mkdir(exist_ok=True)
        (host / "etc" / "config.spec.json").write_text(
            json.dumps({"remotes": {"amp-mcp": {"config": "amp", "directory": str(target), "pattern": "*.json", "disabled_suffix": ".disabled"}}}),
            encoding="utf-8",
        )
        command = host / "bin" / "config" / "command.mjs"
        command.parent.mkdir()
        command.write_text(
            "#!/bin/sh\n"
            "[ \"$1\" = --action ] && [ \"$2\" = assemble ] && "
            "[ \"$3\" = --context ] && [ \"$4\" = canonical ]\n",
            encoding="utf-8",
        )
        command.chmod(0o770)
        (source / "etc" / "mcp.json").write_text(
            json.dumps({"type": "remote", "url": "https://example.test/mcp"}),
            encoding="utf-8",
        )

        run([str(adapter), str(source)])
        fragment = target / "example.json"
        durable = source / "etc" / "mcp-remote" / "example.json"
        assert fragment.is_symlink() and fragment.resolve() == durable
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
        # The shared core remains directly executable with its original CLI.
        run([str(core), "amp-mcp", "amp.mcpServers", "true", str(source)])

        disabled = fragment.with_suffix(".json.disabled")
        fragment.rename(disabled)
        (source / "etc" / "mcp.json").write_text(
            json.dumps({"type": "remote", "url": "https://example.test/new"}), encoding="utf-8"
        )
        reinstall = run([str(adapter), str(source)], check=False)
        assert reinstall.returncode == 0
        assert not fragment.exists()
        assert "https://example.test/new" in disabled.read_text(encoding="utf-8")
        assert disabled.is_symlink() and disabled.resolve() == durable


if __name__ == "__main__":
    test_mcp_install()
    print("ok: MCP drop-in adapter integration")
