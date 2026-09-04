#!/usr/bin/env python3
"""Exercise STATUS_PROC leaf selection and reporter generation through Ansible."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def generate_status_proc(
    temporary: Path,
    status_proc: list[dict[str, object]],
    *,
    statuses: list[str] | None = None,
    extra: dict[str, object] | None = None,
) -> dict[str, object]:
    temporary.mkdir(parents=True, exist_ok=True)
    payload = temporary / "payload"
    result_file = temporary / "result.json"
    scenario_file = temporary / "scenario.json"
    scenario = {"STATUS_PROC": status_proc, **(extra or {})}
    scenario_file.write_text(json.dumps(scenario), encoding="utf-8")
    (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)

    playbook = temporary / "generate.pb"
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {str(ROOT / 'vars' / 'common.yaml')!r}
  vars:
    TYPE: status-proc-test
    NAME: status-proc-test
    DIR: {str(payload)!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    ENV: {{}}
    ENV_LIST: []
    STATUSES: {json.dumps(statuses or [])}
    STATUS_DIRS: []
    STATUS_DIRS_SUDO: []
    SYSTEMD_SCOPE: system
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_status_proc.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_status.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - ansible.builtin.copy:
        dest: {str(result_file)!r}
        content: "{{{{ {{'bins': BINS, 'statuses': STATUSES}} | to_nice_json }}}}"
        mode: "0600"
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
            "-e",
            f"@{scenario_file}",
        ],
        cwd=temporary,
        env=env,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise AssertionError(
            f"ansible-playbook failed ({result.returncode})\n"
            f"{result.stdout}\n{result.stderr}"
        )

    generated = json.loads(result_file.read_text(encoding="utf-8"))
    generated["scripts"] = {
        path.name: path.read_text(encoding="utf-8")
        for path in (payload / "bin").iterdir()
    } if (payload / "bin").is_dir() else {}
    return generated


def test_status_proc_selects_and_batches_reporters() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-status-proc-") as tmp:
        generated = generate_status_proc(
            Path(tmp),
            [
                {
                    "name": "opencode-watchman-env",
                    "check": "mainpid-env",
                    "unit": "opencode.service",
                    "manager": "user",
                    "expected": {
                        "WATCHMAN_SOCK": "/run/user/1000/watchman/sock",
                    },
                },
                {
                    "name": "watchwoman-env",
                    "check": "mainpid-env",
                    "unit": "watchwoman.service",
                    "manager": "user",
                    "expected": {
                        "WATCHWOMAN_CONFIG_FILE": "/opt/watchwoman/etc/watchwoman.json",
                    },
                },
                {
                    "name": "opencode-executable",
                    "check": "exe-current",
                    "unit": "opencode.service",
                    "expected": "/usr/local/bin/opencode2",
                },
            ],
            statuses=["status-existing.sh"],
        )

        assert generated["statuses"] == [
            "status-existing.sh",
            "status-mainpid-env.sh",
            "status-exe-current.sh",
        ]
        by_name = {item["name"]: item for item in generated["bins"]}
        assert set(by_name) == {
            "status-mainpid-env.sh",
            "status-exe-current.sh",
            "status.sh",
        }
        assert "status-proc.sh" not in by_name

        mainpid = by_name["status-mainpid-env.sh"]
        assert mainpid["origin_subsystems"] == ["status_proc_mainpid_env"]
        assert mainpid["bypass_scopes"] == ["status"]
        assert [row["name"] for row in mainpid["status_proc_checks"]] == [
            "opencode-watchman-env",
            "watchwoman-env",
        ]

        executable = by_name["status-exe-current.sh"]
        assert executable["origin_subsystems"] == ["status_proc_exe_current"]
        assert executable["bypass_scopes"] == ["status"]
        assert [row["name"] for row in executable["status_proc_checks"]] == [
            "opencode-executable"
        ]

        scripts = generated["scripts"]
        assert set(scripts) == set(by_name)
        assert "opencode.service" in scripts["status-mainpid-env.sh"]
        assert "WATCHMAN_SOCK" in scripts["status-mainpid-env.sh"]
        assert "/usr/local/bin/opencode2" not in scripts["status-mainpid-env.sh"]
        assert "/usr/local/bin/opencode2" in scripts["status-exe-current.sh"]
        assert "WATCHMAN_SOCK" not in scripts["status-exe-current.sh"]
        for name, script in scripts.items():
            syntax = subprocess.run(
                ["bash", "-n"],
                input=script,
                text=True,
                capture_output=True,
                check=False,
            )
            if syntax.returncode:
                raise AssertionError(f"{name}: invalid shell\n{syntax.stderr}")


def test_status_proc_is_not_ambient() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-status-proc-empty-") as tmp:
        generated = generate_status_proc(Path(tmp), [])
        assert generated == {"bins": [], "statuses": [], "scripts": {}}


def test_status_proc_provider_bypass_disables_all_checks() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-status-proc-bypass-") as tmp:
        generated = generate_status_proc(
            Path(tmp),
            [
                {
                    "name": "opencode-executable",
                    "check": "exe-current",
                    "unit": "opencode.service",
                    "expected": "/usr/local/bin/opencode2",
                }
            ],
            extra={"STATUS_PROC_BYPASS": True},
        )
        assert generated == {"bins": [], "statuses": [], "scripts": {}}


if __name__ == "__main__":
    test_status_proc_selects_and_batches_reporters()
    test_status_proc_is_not_ambient()
    test_status_proc_provider_bypass_disables_all_checks()
    print("ok: STATUS_PROC selectively generates proc-backed status reporters")
