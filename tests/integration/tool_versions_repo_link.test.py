#!/usr/bin/env python3
"""Repo vars must not clean up tool-version paths before the build-mise bin."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "build-mise" / "repo-vars"
VARS_REPO_TASKS = ROOT / "tasks/compfuzor/vars_repo.tasks"


def test_repo_vars_leave_existing_version_paths_untouched() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        deployment = tmp / "deployment"
        deployment.mkdir()
        (deployment / ".tool-versions").write_text("nodejs 26\n")
        checkout = tmp / "repo"
        subprocess.run(["git", "init", "-q", str(checkout)], check=True)
        managed = checkout / ".tool-versions"
        managed.symlink_to(deployment / ".tool-versions")
        existing = checkout / "mise.toml"
        existing.write_text('[tools]\nnodejs = "old"\n')
        playbook = tmp / "vars-render.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(deployment)!r}
    REPO_DIR: {str(checkout)!r}
    ENV: {{}}
    GIT_UPDATE: true
  tasks:
    - import_tasks: {str(VARS_REPO_TASKS)!r}
""")
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        result = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT, env=env, capture_output=True, text=True, check=False,
        )
        if result.returncode:
            raise AssertionError(f"render failed:\n{result.stdout}\n{result.stderr}")
        assert managed.is_symlink() and managed.resolve() == deployment / ".tool-versions"
        assert existing.read_text() == '[tools]\nnodejs = "old"\n'
