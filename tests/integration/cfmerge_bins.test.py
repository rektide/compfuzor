#!/usr/bin/env python3
"""Exercise lazy same-name BINS merges through a real Ansible render."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_lazy_keyed_bins_render() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-cfmerge-bins-") as tmp:
        temporary = Path(tmp)
        output = temporary / "collision.sh"
        playbook = temporary / "render.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  tasks:
    - name: Merge same-name bins before generated values exist
      ansible.builtin.set_fact:
        BINS: "{{{{ base_bins | merge_list(incoming_bins, preset='bins_generated') }}}}"
      vars:
        base_bins:
          - name: collision.sh
            helpers: false
            generated: |
              printf 'base:%s\\n' '{{{{ late_base }}}}'
        incoming_bins:
          - name: collision.sh
            generated: |
              printf 'incoming:%s\\n' '{{{{ late_incoming }}}}'

    - name: Define values only after the merge boundary
      ansible.builtin.set_fact:
        late_base: base-late
        late_incoming: incoming-late

    - name: Render the merged bin
      ansible.builtin.template:
        src: {str(ROOT / 'files' / '_bin')!r}
        dest: {str(output)!r}
        mode: "0755"
      vars:
        item: "{{{{ BINS[0] }}}}"

    - name: Exercise the NVIM narrow keyed merge
      ansible.builtin.set_fact:
        nvim_bins: "{{{{ nvim_left | merge_list(nvim_right, preset={{'name': 'merge_keyed', 'key': 'name', 'concat_fields': ['generated']}}) }}}}"
      vars:
        nvim_left:
          - name: install-nvim.sh
            early: early-left
            generated: generated-left
            run_all: [left.sh]
        nvim_right:
          - name: install-nvim.sh
            early: early-right
            generated: generated-right
            run_all: [right.sh]

    - name: Assert NVIM concatenates generated only
      ansible.builtin.assert:
        that:
          - nvim_bins | length == 1
          - nvim_bins[0].generated == 'generated-left\\ngenerated-right'
          - nvim_bins[0].early == 'early-right'
          - nvim_bins[0].run_all == ['right.sh']
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
                f"ansible-playbook failed ({result.returncode})\n"
                f"{result.stdout}\n{result.stderr}"
            )

        rendered = output.read_text(encoding="utf-8")
        base = "printf 'base:%s\\n' 'base-late'"
        incoming = "printf 'incoming:%s\\n' 'incoming-late'"
        if base not in rendered or incoming not in rendered:
            raise AssertionError(f"missing late-rendered contributions:\n{rendered}")
        if rendered.index(base) >= rendered.index(incoming):
            raise AssertionError("same-name BINS contributions rendered out of order")
        if "{{ late_" in rendered:
            raise AssertionError(f"unresolved lazy template remained:\n{rendered}")

        subprocess.run(["bash", "-n", str(output)], check=True)
        print("ok: lazy same-name BINS merge rendered both contributions in order")
        print("ok: NVIM narrow merge concatenated generated only")


if __name__ == "__main__":
    test_lazy_keyed_bins_render()
