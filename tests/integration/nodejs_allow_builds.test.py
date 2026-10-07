#!/usr/bin/env python3
"""nodejs subsystem dep-build approval renders --allow-build flags on pnpm install."""

from __future__ import annotations

import json
import tempfile
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "nodejs-allow-builds"


def render_build_script(extra_vars: str) -> str:
    with tempfile.TemporaryDirectory(prefix="compfuzor-nodejs-ab-") as tmp:
        temporary = Path(tmp)
        playbook = temporary / "render.pb"
        output = temporary / "out.json"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: allow-builds-test
    NAME: allow-builds-test
    NODEJS: true
    {extra_vars}
  tasks:
    - ansible.builtin.include_vars: {str(ROOT / 'vars/common.yaml')!r}
    - ansible.builtin.set_fact:
        bins: "{{{{ lookup('merge_subsys', id='nodejs', contrib='BINS') }}}}"
    - ansible.builtin.copy:
        dest: {str(output)!r}
        content: "{{{{ bins | to_json }}}}"
""",
            encoding="utf-8",
        )
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        rendered = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        if rendered.returncode:
            raise AssertionError(
                f"ansible-playbook failed ({rendered.returncode})\n"
                f"{rendered.stdout}\n{rendered.stderr}"
            )
        bins = json.loads(output.read_text())
        try:
            build = next(item for item in bins if item["name"] == "build-nodejs.sh")
        except StopIteration:
            raise AssertionError(f"build-nodejs.sh missing from { [i.get('name') for i in bins] }")
        return build["generated"]


def test_default_install_has_no_allow_build_flags() -> None:
    generated = render_build_script("")
    assert "pnpm i --frozen-lockfile\n" in generated
    assert "--allow-build" not in generated


def test_allow_builds_list_appends_flags() -> None:
    generated = render_build_script("NODEJS_ALLOW_BUILDS: [core-js, node-gyp]")
    assert "pnpm i --frozen-lockfile --allow-build=core-js --allow-build=node-gyp\n" in generated


def test_allow_build_singular_alias_and_scalar() -> None:
    generated = render_build_script("NODEJS_ALLOW_BUILD: core-js")
    assert "pnpm i --frozen-lockfile --allow-build=core-js\n" in generated


def test_install_uses_pnpm12_live_link_syntax() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-nodejs-ab-") as tmp:
        temporary = Path(tmp)
        playbook = temporary / "render.pb"
        output = temporary / "out.json"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: allow-builds-test
    NAME: allow-builds-test
    NODEJS: true
  tasks:
    - ansible.builtin.include_vars: {str(ROOT / 'vars/common.yaml')!r}
    - ansible.builtin.set_fact:
        bins: "{{{{ lookup('merge_subsys', id='nodejs', contrib='BINS') }}}}"
    - ansible.builtin.copy:
        dest: {str(output)!r}
        content: "{{{{ bins | to_json }}}}"
""",
            encoding="utf-8",
        )
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        rendered = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        if rendered.returncode:
            raise AssertionError(
                f"ansible-playbook failed ({rendered.returncode})\n"
                f"{rendered.stdout}\n{rendered.stderr}"
            )
        bins = json.loads(output.read_text())
        install = next(item for item in bins if item["name"] == "install-nodejs.sh")
        lines = [line.strip() for line in install["generated"].splitlines()]
        assert not any(line.endswith("pnpm link -g") for line in lines)
        assert "pnpm add -g ." in lines
        assert '(cd "$_cf_dir" && pnpm add -g .)' in lines


if __name__ == "__main__":
    test_default_install_has_no_allow_build_flags()
    test_allow_builds_list_appends_flags()
    test_allow_build_singular_alias_and_scalar()
    test_install_uses_pnpm12_live_link_syntax()
    print("ok: nodejs allow-builds rendering")
