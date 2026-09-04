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
    status_proc: object,
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
    task_dir = ROOT / "tasks" / "compfuzor"
    sub_task = task_dir / "sub_status_proc.tasks"
    gen_task = task_dir / "gen_status_proc.tasks"
    status_task = task_dir / "gen_status.tasks"
    bins_task = task_dir / "bins.tasks"
    result_expression = (
        "{{ {'bins': BINS, 'statuses': STATUSES, "
        "'provider': SUBSYSTEM.status_proc | default({})} | to_nice_json }}"
    )

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
    - ansible.builtin.import_tasks: {str(sub_task)!r}
    - ansible.builtin.import_tasks: {str(gen_task)!r}
    - ansible.builtin.import_tasks: {str(status_task)!r}
    - ansible.builtin.import_tasks: {str(bins_task)!r}
    - ansible.builtin.copy:
        dest: {str(result_file)!r}
        content: {result_expression!r}
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
    generated["scripts"] = (
        {
            path.name: path.read_text(encoding="utf-8")
            for path in (payload / "bin").iterdir()
        }
        if (payload / "bin").is_dir()
        else {}
    )
    return generated


def require_rejected_status_proc(
    status_proc: object,
    expected: str,
    *,
    extra: dict[str, object] | None = None,
) -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-status-proc-invalid-") as tmp:
        try:
            generate_status_proc(Path(tmp), status_proc, extra=extra)
        except AssertionError as error:
            if expected not in str(error):
                raise AssertionError(
                    f"expected generation error containing {expected!r}\n{error}"
                ) from error
        else:
            raise AssertionError(f"STATUS_PROC unexpectedly accepted {status_proc!r}")


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
        assert mainpid["origin_subsystems"] == ["status_proc"]
        assert mainpid["bypass_scopes"] == ["status"]
        assert [row["name"] for row in mainpid["status_proc_checks"]] == [
            "opencode-watchman-env",
            "watchwoman-env",
        ]

        executable = by_name["status-exe-current.sh"]
        assert executable["origin_subsystems"] == ["status_proc"]
        assert executable["bypass_scopes"] == ["status"]
        assert [row["name"] for row in executable["status_proc_checks"]] == [
            "opencode-executable"
        ]

        provider = generated["provider"]
        assert {
            "status": provider["status"],
            "requested": provider["requested"],
            "bypassed": provider["bypassed"],
            "valid": provider["valid"],
            "active": provider["active"],
            "reasons": provider["reasons"],
        } == {
            "status": "active",
            "requested": True,
            "bypassed": False,
            "valid": True,
            "active": True,
            "reasons": [],
        }
        assert [row["manager"] for row in provider["spec"]] == [
            "user",
            "user",
            "system",
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
        assert generated == {
            "bins": [],
            "statuses": [],
            "provider": {},
            "scripts": {},
        }


def test_status_proc_provider_bypass_disables_all_checks() -> None:
    for index, status_proc in enumerate(
        [
            "malformed",
            {"check": "exe-current"},
            [
                {
                    "name": "opencode-executable",
                    "check": "exe-current",
                    "unit": "opencode.service",
                    "expected": "/usr/local/bin/opencode2",
                }
            ],
        ]
    ):
        with tempfile.TemporaryDirectory(
            prefix=f"compfuzor-status-proc-bypass-{index}-"
        ) as tmp:
            generated = generate_status_proc(
                Path(tmp),
                status_proc,
                extra={"STATUS_PROC_BYPASS": True},
            )
            assert generated == {
                "bins": [],
                "statuses": [],
                "provider": {},
                "scripts": {},
            }


def test_status_proc_rejects_invalid_typed_fields() -> None:
    require_rejected_status_proc(
        [
            {
                "name": "bad-env",
                "check": "mainpid-env",
                "unit": "demo.service",
                "expected": {"DEMO": ["not", "scalar"]},
            }
        ],
        "expected values must be strings",
    )
    require_rejected_status_proc(
        [
            {
                "name": "bad-manager",
                "check": "exe-current",
                "unit": "demo.service",
                "expected": "/usr/bin/demo",
            }
        ],
        "manager must resolve to system or user",
        extra={"SYSTEMD_SCOPE": "invalid"},
    )
    require_rejected_status_proc(
        [
            {
                "name": "future-check",
                "check": "future",
                "unit": "demo.service",
                "expected": "unused",
            }
        ],
        "kind 'future' has no validator",
        extra={
            "_STATUS_PROC_KINDS": {
                "future": {
                    "reporter": "status-future.sh",
                    "src": "../status/status-future.sh",
                }
            }
        },
    )


if __name__ == "__main__":
    test_status_proc_selects_and_batches_reporters()
    test_status_proc_is_not_ambient()
    test_status_proc_provider_bypass_disables_all_checks()
    test_status_proc_rejects_invalid_typed_fields()
    print("ok: STATUS_PROC selectively generates proc-backed status reporters")
