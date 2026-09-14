#!/usr/bin/env python3
"""Exercise manually selected filesystem layout profiles through Ansible."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def render(*profiles: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="compfuzor-fs-profile-") as tmp:
        temporary = Path(tmp)
        output = temporary / "result.json"
        playbook = temporary / "profile.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {str(ROOT / 'vars' / 'common.yaml')!r}
  vars:
    TYPE: profile
    NAME: profile-main
    DIR: "{{{{SRCS_DIR}}}}/profile-main"
    DIRSET: [etc, src, pid]
    ETC: "{{{{ETCS_DIR}}}}/profile-main"
    SRC: "{{{{SRCS_DIR}}}}/profile-main"
    PID: "{{{{PIDS_DIR}}}}/profile-main"
    FILES: []
    ETC_FILES:
      - name: app.conf
        content: enabled
    SRC_FILES:
      - name: source.txt
        content: source
    PID_FILES: []
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'compile_artifacts.tasks')!r}
    - ansible.builtin.copy:
        dest: {str(output)!r}
        content: >-
          {{{{ {{'dir': DIR,
                'etc': ETC,
                'src': SRC,
                'pid': PID,
                'global_bins': GLOBAL_BINS_DIR,
                'artifacts': _ARTIFACTS}} | to_json }}}}
""",
            encoding="utf-8",
        )

        command = [
            "ansible-playbook",
            "-i",
            "localhost,",
            "-c",
            "local",
            str(playbook),
            "-e",
            '{"TYPE":"profile","NAME":"profile-main"}',
        ]
        for profile in profiles:
            command.extend(["-e", f"@{ROOT / 'vars' / profile}"])

        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise AssertionError(f"ansible-playbook failed\n{result.stdout}\n{result.stderr}")
        return json.loads(output.read_text(encoding="utf-8"))


def family(result: dict, name: str) -> dict:
    return result["artifacts"]["families"][name]


def test_default_layout() -> None:
    result = render()
    assert result["dir"] == "/usr/local/src/profile-main"
    assert family(result, "ETC_FILES")["materialized_root"] == "/etc/opt/profile-main"
    assert family(result, "ETC_FILES")["exposure_root"] == "/usr/local/src/profile-main/etc"
    print("ok: unset root variables retain the normal split layout")


def test_steamos_layout() -> None:
    result = render("steamos.yml")
    assert result["dir"] == "/opt/compfuzor/src/profile-main"
    assert result["etc"] == "/opt/compfuzor/etc/profile-main"
    assert result["pid"] == "/run/compfuzor/profile-main"
    assert result["global_bins"] == "/opt/compfuzor/bin"
    assert family(result, "ETC_FILES")["materialized_root"] == result["etc"]
    assert family(result, "ETC_FILES")["exposure_root"] == result["dir"] + "/etc"
    print("ok: SteamOS profile redirects durable bases under /opt and runtime under /run")


def test_stacked_container_layout() -> None:
    result = render("steamos.yml", "containered.yml")
    assert family(result, "ETC_FILES")["materialized_root"] == result["dir"] + "/etc"
    assert family(result, "ETC_FILES")["exposure_root"] == result["etc"]
    assert family(result, "SRC_FILES")["materialized_root"] == result["dir"]
    assert family(result, "SRC_FILES")["exposure_root"] == result["dir"]
    print("ok: containered profile composes with SteamOS and avoids identical-root inversion")


if __name__ == "__main__":
    test_default_layout()
    test_steamos_layout()
    test_stacked_container_layout()
