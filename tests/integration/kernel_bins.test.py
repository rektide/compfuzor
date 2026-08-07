#!/usr/bin/env python3
"""Exercise the production gen_kernel -> gen_bins hierarchy through Ansible."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def generate_kernel_bins(temporary: Path, scenario: dict[str, object]) -> list[dict]:
    temporary.mkdir(parents=True, exist_ok=True)
    output = temporary / "bins.json"
    scenario_file = temporary / "scenario.json"
    scenario_file.write_text(json.dumps(scenario), encoding="utf-8")
    playbook = temporary / "generate.pb"
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {str(ROOT / 'vars' / 'common.yaml')!r}
  vars:
    TYPE: kernel-hierarchy-test
    NAME: kernel-hierarchy-test
    DIR: {str(temporary / 'payload')!r}
    ETC: {str(temporary / 'payload' / 'etc')!r}
    BINS: []
    ETC_FILES: []
    ENV: {{}}
    ENV_LIST: []
    PKGS: []
    STATUSES: []
    KERNEL_BYPASS: false
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_kernel.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_bins.tasks')!r}
    - ansible.builtin.copy:
        dest: {str(output)!r}
        content: "{{{{ BINS | to_nice_json }}}}"
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
        cwd=ROOT,
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
    return json.loads(output.read_text(encoding="utf-8"))


def require_hierarchy(bins: list[dict], expected: dict[str, list[str]]) -> None:
    by_name = {item["name"]: item for item in bins}
    for item in bins:
        source = item.get("src")
        if source:
            source_path = ROOT / "files" / source.removeprefix("../")
            if not source_path.is_file():
                raise AssertionError(
                    f"{item['name']}: configured source does not exist: {source}"
                )
    for parent, children in expected.items():
        if parent not in by_name:
            raise AssertionError(f"missing compositor {parent!r}: {sorted(by_name)}")
        compositor = by_name[parent]
        if compositor.get("run_all") != children:
            raise AssertionError(
                f"{parent}: expected {children!r}, got {compositor.get('run_all')!r}"
            )
        if compositor.get("generated_by") != "gen_bins":
            raise AssertionError(f"{parent}: not a generated compositor: {compositor!r}")
        for forbidden in ("src", "content", "generated", "bypass"):
            if forbidden in compositor:
                raise AssertionError(
                    f"{parent}: pure compositor contains {forbidden}: {compositor!r}"
                )


def test_production_kernel_hierarchy() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-kernel-bins-") as tmp:
        temporary = Path(tmp)
        complete = generate_kernel_bins(
            temporary,
            {
                "KERNEL_MODULES": {"loop": {"params": {"max_loop": 8}}},
                "KERNEL_SYSCTL": {"kernel.panic": 10},
                "KERNEL_SYSFS": {"/sys/kernel/test": 1},
                "KERNEL_PARAMS": ["printk.time=1"],
            },
        )
        require_hierarchy(
            complete,
            {
                "build.sh": ["build-kernel.sh"],
                "build-kernel.sh": [
                    "build-kernel-modprobe.sh",
                    "build-kernel-sysctl.sh",
                    "build-kernel-sysfs.sh",
                ],
                "install.sh": ["install-kernel.sh"],
                "install-kernel.sh": [
                    "install-kernel-modprobe.sh",
                    "install-kernel-sysctl.sh",
                    "install-kernel-sysfs.sh",
                    "install-kernel-params.sh",
                    "install-kernel-bls.sh",
                ],
                "apply.sh": ["apply-kernel.sh"],
                "apply-kernel.sh": [
                    "apply-kernel-modprobe.sh",
                    "apply-kernel-sysctl.sh",
                    "apply-kernel-sysfs.sh",
                ],
            },
        )
        complete_by_name = {item["name"]: item for item in complete}
        for leaf, origin in (
            ("build-kernel-modprobe.sh", "kernel_modprobe"),
            ("build-kernel-sysctl.sh", "kernel_sysctl"),
            ("build-kernel-sysfs.sh", "kernel_sysfs"),
            ("install-kernel-params.sh", "kernel_params"),
            ("install-kernel-bls.sh", "kernel_bls"),
        ):
            item = complete_by_name[leaf]
            if item.get("origin_subsystems") != [origin]:
                raise AssertionError(f"{leaf}: wrong origin metadata: {item!r}")
            if item.get("bypass_scopes") != ["kernel"]:
                raise AssertionError(f"{leaf}: wrong broad scope metadata: {item!r}")
            if item.get("subsystem") != "kernel":
                raise AssertionError(f"{leaf}: compositor grouping changed: {item!r}")

        sysctl_only = generate_kernel_bins(
            temporary / "sysctl-only",
            {
                "KERNEL_MODULES": {},
                "KERNEL_SYSCTL": {"kernel.panic": 10},
                "KERNEL_SYSFS": {},
                "KERNEL_PARAMS": [],
            },
        )
        require_hierarchy(
            sysctl_only,
            {
                "build.sh": ["build-kernel.sh"],
                "build-kernel.sh": ["build-kernel-sysctl.sh"],
                "install.sh": ["install-kernel.sh"],
                "install-kernel.sh": ["install-kernel-sysctl.sh"],
                "apply.sh": ["apply-kernel.sh"],
                "apply-kernel.sh": ["apply-kernel-sysctl.sh"],
            },
        )
        print("ok: production kernel hierarchy is recursive for many and one unit")


if __name__ == "__main__":
    test_production_kernel_hierarchy()
