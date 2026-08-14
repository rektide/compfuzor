#!/usr/bin/env python3
"""Verify BINS filename migrations remove superseded generated scripts."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_bin_replaces_removes_old_filename() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-bin-replaces-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        output = payload / "bin"
        output.mkdir(parents=True)
        old = output / "install-rust.user.sh"
        old.write_text("old\n", encoding="utf-8")

        playbook = temporary / "render.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: direct-tools
    DIR: {str(payload)!r}
    BINS_DIR: {str(output)!r}
    BINMODE: "0755"
    BINS:
      - name: install-rust-user.sh
        replaces: [install-rust.user.sh]
        basedir: false
        content: echo migrated
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/bins.tasks')!r}
""",
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        result = subprocess.run(
            [
                "ansible-playbook",
                "-i",
                "localhost,",
                "-c",
                "local",
                str(playbook),
            ],
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise AssertionError(
                f"ansible-playbook failed ({result.returncode})\n{result.stdout}\n{result.stderr}"
            )

        if old.exists():
            raise AssertionError("superseded bin filename was not removed")
        migrated = output / "install-rust-user.sh"
        if not migrated.is_file() or "echo migrated" not in migrated.read_text(
            encoding="utf-8"
        ):
            raise AssertionError("migrated bin was not rendered")


if __name__ == "__main__":
    test_bin_replaces_removes_old_filename()
    print("ok: replaced bin filenames are removed before rendering")
