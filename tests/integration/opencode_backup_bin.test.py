#!/usr/bin/env python3
"""Render OpenCode's declared TypeScript backup bin without touching the host."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
from textwrap import indent

import yaml


ROOT = Path(__file__).resolve().parents[2]


def test_backup_node_bin() -> None:
    play = yaml.safe_load((ROOT / "opencode.src.pb").read_text(encoding="utf-8"))[0]
    backup = next(record for record in play["vars"]["BINS"] if record["name"] == "backup.ts")
    assert backup["runtime"] == "node" and not backup.get("raw", False)

    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-backup-") as tmp:
        temporary = Path(tmp)
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        deployment = temporary / "deployment"
        rendered_playbook = temporary / "render.pb"
        bin_yaml = indent(yaml.safe_dump([backup], sort_keys=False), "      ")
        rendered_playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: opencode
    DIR: {str(deployment)!r}
    BINS_DIR: {str(deployment / 'bin')!r}
    BINMODE: '0755'
    BINS:
{bin_yaml}  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/bins.tasks')!r}
""",
            encoding="utf-8",
        )
        result = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(rendered_playbook)],
            cwd=ROOT,
            env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"{result.stdout}\n{result.stderr}"
        binary = deployment / "bin" / "backup.ts"
        text = binary.read_text(encoding="utf-8")
        assert text.startswith("#!/usr/bin/env node\n/**\n")
        assert text.count("#!/usr/bin/env node") == 1
        help_result = subprocess.run([str(binary), "--help"], capture_output=True, text=True)
        assert help_result.returncode == 0, help_result.stderr
        assert "BACKUP_TARGETS" in help_result.stdout


if __name__ == "__main__":
    test_backup_node_bin()
    print("ok: opencode backup.ts Node bin")
