#!/usr/bin/env python3
"""Verify BINS tombstones suppress subsystem leaves and remove stale files."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_bin_tombstone_materialization() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-bin-tombstone-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        output = payload / "bin"
        playbook = temporary / "render.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: tombstone-test
    DIR: {str(payload)!r}
    BINS_DIR: {str(output)!r}
    BINMODE: '0755'
    NODEJS: true
    BINS:
      - name: build-nodejs.sh
        state: absent
    SUBSYSTEM:
      nodejs:
        contrib:
          BINS:
            - name: build-nodejs.sh
              generated: echo build
            - name: apply-live.sh
              generated: echo apply
  tasks:
    - ansible.builtin.file:
        path: {str(output)!r}
        state: directory
        mode: '0771'
    - ansible.builtin.copy:
        dest: {str(output / 'build-nodejs.sh')!r}
        content: stale
        mode: '0755'
    - ansible.builtin.set_fact:
        BINS: "{{{{ lookup('merge_subsys', id='nodejs', contrib='BINS') }}}}"
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/gen_bins.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/bins.tasks')!r}
""",
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        rendered = subprocess.run(
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
        if rendered.returncode:
            raise AssertionError(
                f"ansible-playbook failed ({rendered.returncode})\n"
                f"{rendered.stdout}\n{rendered.stderr}"
            )

        names = {path.name for path in output.iterdir()}
        if names != {"apply-live.sh", "apply.sh"}:
            raise AssertionError(f"unexpected materialized bins: {sorted(names)}")
        if "build-nodejs.sh" in names or "build.sh" in names:
            raise AssertionError(f"tombstoned build was composed: {sorted(names)}")
        print("ok: bin tombstone removes stale leaf and prevents empty compositor")


if __name__ == "__main__":
    test_bin_tombstone_materialization()
