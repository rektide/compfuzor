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
    (playbook.parent / "_cf_action").symlink_to(ROOT / "files" / "_cf_action")
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(output.parent)!r}
    TYPE: direct-tools
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
        - name: build-go.sh
          origin_subsystems: [go]
          bypass_scopes: [go]
          content: echo automatic
        - name: install-rust.user.sh
          origin_subsystems: [rust, shared]
          bypass_scopes: [rust]
          verb: install selected tools
          content: echo qualified
        - name: bypass-list-unit.sh
          origin_subsystems: [go]
          bypass_scopes: [go]
          bypass: [BUILD, "LINK:SERVICE"]
          content: echo list-unit
        - name: apply-network.sh
          content: echo fallback
        - name: bypass-false.sh
          origin_subsystems: [go]
          bypass_scopes: [go]
          bypass: false
          content: echo false
        - name: helpers-false.sh
          helpers: false
          origin_subsystems: [go]
          bypass_scopes: [go]
          content: echo nuclear
        - name: loud-state.sh
          basedir: false
          bypass: false
          content: printf '%s\\n' "$_cf_loud"
        - name: macro.sh
          basedir: false
          bypass: false
          helpers: [report, guard]
          content: |
            {{% from "_cf_action" import cf_action %}}
            {{% call cf_action(name='macro.sh', verb='exercise macro', bypass='MACRO', subsystems=['manual']) %}}
            echo macro
            {{% endcall %}}
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
            "build-go.sh",
            "install-rust.user.sh",
            "bypass-list-unit.sh",
            "apply-network.sh",
            "bypass-false.sh",
            "helpers-false.sh",
            "loud-state.sh",
            "macro.sh",
        }:
            raise AssertionError(f"unexpected rendered scripts: {sorted(scripts)}")

        automatic = scripts["build-go.sh"]
        require(automatic, "# report helper:", "automatic bypass")
        require(automatic, "# guard helper:", "automatic bypass")
        require(automatic, '_cf_guard_bypass "GO" "build"', "automatic broad")
        require(
            automatic,
            '_cf_guard_bypass_unit "GO" "BUILD" "build"',
            "automatic nested action",
        )
        require(
            automatic,
            '_cf_action_init "build-go.sh" "build" "go"',
            "actual filename and report",
        )
        require(automatic, "\n_cf_action_end\n", "automatic bypass")

        qualified = scripts["install-rust.user.sh"]
        require(
            qualified,
            '_cf_action_init "install-rust.user.sh" "install selected tools" "rust, shared"',
            "qualified actual filename, explicit verb, and labels",
        )

        list_unit = scripts["bypass-list-unit.sh"]
        require(list_unit, '_cf_guard_bypass "GO" "bypass list unit"', "automatic extension")
        require(list_unit, '_cf_guard_bypass "BUILD" "bypass list unit"', "global phase guard")
        require(
            list_unit,
            '_cf_guard_bypass_unit "LINK" "SERVICE" "bypass list unit"',
            "unit bypass",
        )

        fallback = scripts["apply-network.sh"]
        require(fallback, '_cf_guard_bypass "DIRECT_TOOLS" "apply network"', "TYPE fallback broad")
        require(
            fallback,
            '_cf_guard_bypass_unit "DIRECT_TOOLS" "APPLY_NETWORK" "apply network"',
            "TYPE fallback action",
        )
        require(
            fallback,
            '_cf_action_init "apply-network.sh" "apply network" "direct-tools"',
            "TYPE fallback report label",
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

        macro = scripts["macro.sh"]
        require(
            macro,
            '_cf_action_init "macro.sh" "exercise macro" "manual"',
            "explicit macro report labels",
        )
        require(
            macro,
            '_cf_guard_bypass "MACRO" "exercise macro"',
            "explicit macro guard remains authored",
        )

        automatic_path = output / "build-go.sh"
        run = subprocess.run(
            [str(automatic_path)], check=True, text=True, capture_output=True
        )
        if run.stdout.strip() != "automatic":
            raise AssertionError(f"automatic run body missing: {run!r}")
        require(run.stderr, "+ build-go.sh: build (go)", "automatic loud report")
        skipped_env = os.environ.copy()
        skipped_env["COMPFUZOR_GO_BYPASS"] = "1"
        skipped = subprocess.run(
            [str(automatic_path)],
            check=True,
            text=True,
            capture_output=True,
            env=skipped_env,
        )
        if skipped.stdout:
            raise AssertionError(f"bypassed body executed: {skipped.stdout!r}")
        require(skipped.stderr, "skipped build-go.sh:", "automatic skip report")
        require(skipped.stderr, "(go)", "automatic skip labels")

        fallback_env = os.environ.copy()
        fallback_env["COMPFUZOR_DIRECT_TOOLS_APPLY_NETWORK_BYPASS"] = "1"
        fallback_skipped = subprocess.run(
            [str(output / "apply-network.sh")],
            check=True,
            text=True,
            capture_output=True,
            env=fallback_env,
        )
        if fallback_skipped.stdout:
            raise AssertionError(
                f"TYPE-fallback bypassed body executed: {fallback_skipped.stdout!r}"
            )
        require(
            fallback_skipped.stderr,
            "(direct-tools)",
            "TYPE fallback executed report label",
        )

        loud_state = output / "loud-state.sh"
        loud_cases = (
            ({}, "1", False, "unset V is loud"),
            ({"V": ""}, "1", False, "empty V is loud"),
            ({"V": "0"}, "0", False, "V=0 is quiet"),
            ({"V": "1"}, "1", False, "V=1 is loud"),
            ({"V": "3"}, "1", True, "V>2 enables xtrace"),
            ({"COMPFUZOR_QUIET": "1", "V": "1"}, "0", False, "quiet override wins"),
        )
        for overrides, expected, traces, label in loud_cases:
            env = os.environ.copy()
            env.pop("COMPFUZOR_QUIET", None)
            env.pop("V", None)
            env.update(overrides)
            result = subprocess.run(
                [str(loud_state)],
                check=True,
                text=True,
                capture_output=True,
                env=env,
            )
            if result.stdout.strip() != expected:
                raise AssertionError(
                    f"{label}: expected {expected!r}, got {result.stdout.strip()!r}"
                )
            if traces != bool(result.stderr.strip()):
                raise AssertionError(
                    f"{label}: expected xtrace={traces}, got stderr={result.stderr!r}"
                )
            print(f"ok: {label}")

        for name, script in scripts.items():
            path = output / name
            subprocess.run(["bash", "-n", str(path)], check=True)
            print(f"ok: {name} ({len(script.splitlines())} lines, bash -n)")


if __name__ == "__main__":
    test_rendered_helpers()
