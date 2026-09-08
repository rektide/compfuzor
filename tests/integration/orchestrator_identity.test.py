#!/usr/bin/env python3
"""Generated action/status orchestrators pin their own deployment identity."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_status_orchestrator_ignores_ambient_dir() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-orchestrator-identity-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        playbook = temporary / "render.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files: [{str(ROOT / 'vars' / 'common.yaml')!r}]
  vars:
    TYPE: identity-test
    NAME: identity-test
    DIR: {str(payload)!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS:
      - name: status.sh
        src: ../status/status.sh
        basedir: false
        deployment_rooted: true
        compose: false
      - name: status-sentinel.sh
        content: 'echo intended-reporter; exit 1'
        compose: false
    STATUSES: [status-sentinel.sh]
  tasks:
    - file: {{path: {str(payload / 'bin')!r}, state: directory}}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
""",
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        rendered = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        if rendered.returncode:
            raise AssertionError(f"render failed\n{rendered.stdout}\n{rendered.stderr}")

        foreign = temporary / "foreign"
        (foreign / "bin").mkdir(parents=True)
        (foreign / "bin" / "status-sentinel.sh").write_text("#!/bin/sh\necho foreign-reporter\nexit 0\n", encoding="utf-8")
        (foreign / "bin" / "status-sentinel.sh").chmod(0o755)
        for ambient in (foreign, temporary / "missing"):
            runtime = os.environ.copy()
            runtime["DIR"] = str(ambient)
            result = subprocess.run(
                [str(payload / "bin" / "status.sh")],
                env=runtime,
                text=True,
                capture_output=True,
                check=False,
            )
            assert result.returncode == 1
            assert "intended-reporter" in result.stdout
            assert "foreign-reporter" not in result.stdout


if __name__ == "__main__":
    test_status_orchestrator_ignores_ambient_dir()
    print("ok: deployment-rooted status orchestrator")
