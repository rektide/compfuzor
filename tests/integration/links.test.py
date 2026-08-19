#!/usr/bin/env python3
"""Exercise artifact compilation and deferred link composition through Ansible."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_link_generation() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        output = temporary / "result.json"
        playbook = temporary / "generate.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {str(ROOT / 'vars' / 'common.yaml')!r}
  vars:
    TYPE: link-test
    NAME: link-test
    DIR: {str(payload)!r}
    DIRSET: [etc, share]
    ETC: {str(temporary / 'etc' / 'link-test')!r}
    SHARE: {str(temporary / 'share' / 'link-test')!r}
    FILES: []
    ETC_FILES:
      - name: app.json
        content: '{{"enabled":true}}'
        link: user
      - name: desktop
        content: desktop
        links:
          - scope: user
            dest:
              fsh: share
              name: applications/link-test.desktop
    SHARE_FILES: []
    BINS: []
    ENV: {{}}
    ENV_LIST: []
    STATUSES: []
    LINKS: []
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'compile_artifacts.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_links.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_bins.tasks')!r}
    - ansible.builtin.file:
        path: {str(payload)!r}
        state: directory
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'link_plan.tasks')!r}
    - ansible.builtin.copy:
        dest: {str(output)!r}
        content: "{{{{ {{'plan': _LINK_PLAN, 'bins': BINS, 'statuses': STATUSES}} | to_nice_json }}}}"
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
                '{"TYPE":"link-test","NAME":"link-test"}',
            ],
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise AssertionError(f"ansible-playbook failed\n{result.stdout}\n{result.stderr}")

        generated = json.loads(output.read_text(encoding="utf-8"))
        plan = generated["plan"]
        assert (payload / "links.json").is_file()
        assert plan["links"][0]["src"] == str(temporary / "etc/link-test/app.json")
        assert plan["links"][0]["dest"] == "${HOME}/.config/link-test/app.json"
        assert plan["links"][1]["dest"] == "${HOME}/.local/usr/share/link-test/applications/link-test.desktop"
        by_name = {item["name"]: item for item in generated["bins"]}
        assert by_name["install-links-user.sh"]["run_all"] == ["install-link-records-user.sh"]
        assert "install-links-user.sh" in by_name["install-user.sh"]["run_all"]
        assert "status-links.sh" in generated["statuses"]
        print("ok: deferred links compile and compose through Ansible")


if __name__ == "__main__":
    test_link_generation()
