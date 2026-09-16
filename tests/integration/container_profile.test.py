#!/usr/bin/env python3
"""Exercise the contained vars profile: materialize under DIR, reversed link."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def test_container_profile() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-container-") as temporary:
        scratch = Path(temporary)
        opts = scratch / "opt"
        etcs = scratch / "etc-opt"
        opts.mkdir()
        etcs.mkdir()
        playbook = ROOT / ".test-agent-container-probe.opt.pb"
        output = scratch / "result.json"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {ROOT}/vars/common.yaml
  vars:
    TYPE: container-probe
    type: opt
    NAME: container-probe-main
    DIR: {opts}/container-probe-main
    DIRSET: [etc]
    ETC_FILES:
      - name: app.conf
        content: x
  tasks:
    - ansible.builtin.import_tasks: tasks/compfuzor/compile_artifacts.tasks
    - ansible.builtin.import_tasks: tasks/compfuzor/fs_base.tasks
    - ansible.builtin.import_tasks: tasks/compfuzor/fs_hierarchy.tasks
      vars:
        include: etc
        upper: ETC
    - ansible.builtin.stat:
        path: "{{{{ETC_LINK}}}}"
        follow: false
      register: exposure
    - ansible.builtin.assert:
        that:
          - type == 'opt'
          - ETC == DIR + '/etc'
          - _ARTIFACTS.families.ETC_FILES.materialized_root == ETC
          - exposure.stat.islnk
          - exposure.stat.lnk_source == ETC
    - ansible.builtin.copy:
        dest: {output}
        content: "{{{{ {{'etc': ETC, 'link': ETC_LINK}} | to_json }}}}"
""",
            encoding="utf-8",
        )
        try:
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
                    f"@{ROOT / 'vars' / 'containered.yml'}",
                    "-e",
                    json.dumps(
                        {
                            "TYPE": "container-probe",
                            "NAME": "container-probe-main",
                            "OPTS_DIR": str(opts),
                            "ETCS_DIR": str(etcs),
                            "COMPFUZOR_SHOULD_BECOME": False,
                        }
                    ),
                ],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
            )
        finally:
            playbook.unlink(missing_ok=True)
        if result.returncode:
            raise AssertionError(f"container profile render failed:\n{result.stdout}\n{result.stderr}")
        rendered = json.loads(output.read_text(encoding="utf-8"))
        expected = f"{opts}/container-probe-main/etc"
        if rendered["etc"] != expected:
            raise AssertionError(rendered)
        if rendered["link"] != f"{etcs}/container-probe-main":
            raise AssertionError(rendered)
    print("ok: container profile materializes under DIR with reversed exposure link")


if __name__ == "__main__":
    test_container_profile()
