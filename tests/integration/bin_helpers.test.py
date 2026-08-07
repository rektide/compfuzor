#!/usr/bin/env python3
"""Render files/_bin through Ansible and verify helper/bypass contracts."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def require(text: str, fragment: str, label: str) -> None:
    if fragment not in text:
        raise AssertionError(f"{label}: missing {fragment!r}")


def reject(text: str, fragment: str, label: str) -> None:
    if fragment in text:
        raise AssertionError(f"{label}: unexpectedly contains {fragment!r}")


def render_bins(output: Path, playbook: Path) -> None:
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(output.parent)!r}
  tasks:
    - ansible.builtin.file:
        path: {str(output)!r}
        state: directory
        mode: "0771"
    - ansible.builtin.template:
        src: {str(ROOT / 'files' / '_bin')!r}
        dest: '{str(output)}/{{{{ item.name }}}}'
        mode: "0755"
      loop:
        - name: plain.sh
          content: echo plain
        - name: bypass-scalar.sh
          bypass: LINK
          content: echo scalar
        - name: bypass-list-unit.sh
          bypass: [BUILD, "LINK:SERVICE"]
          content: echo list-unit
        - name: bypass-false.sh
          bypass: false
          content: echo false
        - name: helpers-false.sh
          helpers: false
          bypass: LINK
          content: echo nuclear
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
        ],
        cwd=ROOT,
        env=env,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise AssertionError(
            f"ansible-playbook failed ({result.returncode})\n{result.stdout}\n{result.stderr}"
        )


def test_rendered_helpers() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-bin-helpers-") as tmp:
        temporary = Path(tmp)
        output = temporary / "out" / "bin"
        render_bins(output, temporary / "render.pb")

        scripts = {path.name: path.read_text(encoding="utf-8") for path in output.iterdir()}
        if set(scripts) != {
            "plain.sh",
            "bypass-scalar.sh",
            "bypass-list-unit.sh",
            "bypass-false.sh",
            "helpers-false.sh",
        }:
            raise AssertionError(f"unexpected rendered scripts: {sorted(scripts)}")

        plain = scripts["plain.sh"]
        for helper in ("env", "setopts", "loud"):
            require(plain, f"# {helper} helper:", "plain defaults")
        reject(plain, "# report helper:", "plain defaults")
        reject(plain, "_cf_action_init", "plain defaults")

        scalar = scripts["bypass-scalar.sh"]
        require(scalar, "# report helper:", "scalar bypass")
        require(scalar, "# guard helper:", "scalar bypass")
        require(scalar, '_cf_guard_bypass "LINK" "running"', "scalar bypass")
        require(scalar, '_cf_action_init "bypass-scalar.sh" "running"', "scalar bypass")
        require(scalar, "\n_cf_action_end\n", "scalar bypass")

        list_unit = scripts["bypass-list-unit.sh"]
        require(list_unit, '_cf_guard_bypass "BUILD" "running"', "list bypass")
        require(
            list_unit,
            '_cf_guard_bypass_unit "LINK" "SERVICE" "running"',
            "unit bypass",
        )

        bypass_false = scripts["bypass-false.sh"]
        for helper in ("env", "setopts", "loud"):
            require(bypass_false, f"# {helper} helper:", "false bypass defaults")
        reject(bypass_false, "# report helper:", "false bypass")
        reject(bypass_false, "# guard helper:", "false bypass")
        reject(bypass_false, "_cf_action_init", "false bypass")
        reject(bypass_false, "_cf_action_end", "false bypass")

        nuclear = scripts["helpers-false.sh"]
        reject(nuclear, " helper:", "helpers false")
        reject(nuclear, "_cf_action_init", "helpers false")
        reject(nuclear, "_cf_action_end", "helpers false")
        require(nuclear, "echo nuclear", "helpers false content")

        for name, script in scripts.items():
            path = output / name
            subprocess.run(["bash", "-n", str(path)], check=True)
            print(f"ok: {name} ({len(script.splitlines())} lines, bash -n)")


if __name__ == "__main__":
    test_rendered_helpers()
