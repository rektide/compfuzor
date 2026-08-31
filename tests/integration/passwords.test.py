#!/usr/bin/env python3
"""Verify persisted password permissions, reuse, and Ansible redaction."""

from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run_playbook(playbook: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
    return subprocess.run(
        [
            "ansible-playbook",
            "-vvv",
            "-i",
            "localhost,",
            "-c",
            "local",
            str(playbook),
        ],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def test_persisted_password_is_private_reused_and_redacted() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-passwords-") as temporary:
        directory = Path(temporary)
        secrets = directory / "secrets"
        playbook = directory / "password.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    ETC: {str(directory / 'etc')!r}
    PASSWORDS_DIR: {str(secrets)!r}
    PASSWORDS:
      - name: TEST_PASSWORD
        format: "python3 -c 'import secrets; print(secrets.token_urlsafe(32))'"
        per_host: true
        file: true
  tasks:
    - import_tasks: {ROOT / 'tasks/compfuzor/gen_passwords.tasks'}
""",
            encoding="utf-8",
        )

        first = run_playbook(playbook)
        if first.returncode != 0:
            raise AssertionError(f"password generation failed:\n{first.stdout}{first.stderr}")

        password_file = secrets / "TEST_PASSWORD"
        password = password_file.read_text(encoding="utf-8")
        if len(password) != 43:
            raise AssertionError(f"expected a 43-character password, got {len(password)}")
        directory_mode = stat.S_IMODE(secrets.stat().st_mode)
        file_mode = stat.S_IMODE(password_file.stat().st_mode)
        if directory_mode != 0o700 or file_mode != 0o600:
            raise AssertionError(
                f"unexpected password modes: directory={directory_mode:o} file={file_mode:o}"
            )
        if password in first.stdout + first.stderr:
            raise AssertionError("generated password leaked into verbose Ansible output")

        second = run_playbook(playbook)
        if second.returncode != 0:
            raise AssertionError(f"password reuse failed:\n{second.stdout}{second.stderr}")
        if password_file.read_text(encoding="utf-8") != password:
            raise AssertionError("persisted password changed on the second render")
        if password in second.stdout + second.stderr:
            raise AssertionError("persisted password leaked into verbose Ansible output")


if __name__ == "__main__":
    test_persisted_password_is_private_reused_and_redacted()
    print("ok: persisted password permissions and redaction")
