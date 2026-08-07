#!/usr/bin/env python3
"""Exercise body-local disarm after canonical BINS/compositor collisions."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def require(text: str, fragment: str, label: str) -> None:
    if fragment not in text:
        raise AssertionError(f"{label}: missing {fragment!r}\n{text}")


def reject(text: str, fragment: str, label: str) -> None:
    if fragment in text:
        raise AssertionError(f"{label}: unexpectedly contains {fragment!r}\n{text}")


def run_script(path: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(path)],
        check=True,
        text=True,
        capture_output=True,
        env=env,
    )


def body_output(result: subprocess.CompletedProcess) -> list[str]:
    return [
        line
        for line in result.stdout.splitlines()
        if not line.startswith("+ ") and line != "complete"
    ]


def test_canonical_body_disarm_is_local_to_compositor_body() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-compositor-disarm-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        output = payload / "bin"
        playbook = temporary / "render.pb"
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: direct-tools
    DIR: {str(payload)!r}
    BINS:
      - name: build.sh
        content: echo direct-body
      - name: build-child.sh
        content: echo direct-child
      - name: install.sh
        origin_subsystems: [canonical-author]
        bypass_scopes: [canonical]
        content: echo annotated-body
      - name: install-child.sh
        origin_subsystems: [install-child]
        bypass_scopes: [install-child]
        content: echo annotated-child
      - name: apply.sh
        origin_subsystems: [metadata-only]
        bypass_scopes: [metadata-only]
        bypass: APPLY
      - name: apply-child.sh
        content: echo pure-child
  tasks:
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/gen_bins.tasks')!r}
    - ansible.builtin.file:
        path: {str(output)!r}
        state: directory
        mode: "0771"
    - ansible.builtin.template:
        src: {str(ROOT / 'files/_bin')!r}
        dest: '{str(output)}/{{{{ item.name }}}}'
        mode: "0755"
      loop: "{{{{ BINS }}}}"
""",
            encoding="utf-8",
        )

        ansible_env = os.environ.copy()
        ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        rendered = subprocess.run(
            [
                "ansible-playbook",
                "-i",
                "localhost,",
                "-c",
                "local",
                str(playbook),
            ],
            cwd=ROOT,
            env=ansible_env,
            check=False,
            text=True,
            capture_output=True,
        )
        if rendered.returncode:
            raise AssertionError(
                f"ansible-playbook failed ({rendered.returncode})\n"
                f"{rendered.stdout}\n{rendered.stderr}"
            )

        build_text = (output / "build.sh").read_text(encoding="utf-8")
        install_text = (output / "install.sh").read_text(encoding="utf-8")
        apply_text = (output / "apply.sh").read_text(encoding="utf-8")
        require(build_text, "_cf_body_run=1", "direct canonical body-local guard")
        require(
            build_text,
            '_cf_action_init "build.sh" "build" "direct-tools"',
            "direct canonical fallback report",
        )
        require(install_text, "_cf_body_run=1", "annotated canonical body-local guard")
        require(
            install_text,
            '_cf_action_init "install.sh" "install" "canonical-author"',
            "annotated canonical report",
        )
        reject(apply_text, "_cf_action_init", "pure generated compositor")
        reject(apply_text, "# guard helper:", "pure generated compositor")

        for path in output.iterdir():
            subprocess.run(["bash", "-n", str(path)], check=True)

        passed = run_script(output / "build.sh")
        if body_output(passed) != ["direct-body", "direct-child"]:
            raise AssertionError(f"passing body/child order changed: {passed!r}")

        direct_skip_env = os.environ.copy()
        direct_skip_env["COMPFUZOR_DIRECT_TOOLS_BUILD_BYPASS"] = "1"
        direct_skipped = run_script(output / "build.sh", direct_skip_env)
        if body_output(direct_skipped) != ["direct-child"]:
            raise AssertionError(f"body skip suppressed direct child: {direct_skipped!r}")
        require(direct_skipped.stderr, "skipped build.sh:", "direct body skip report")
        require(direct_skipped.stderr, "(direct-tools)", "direct fallback label")

        annotated_skip_env = os.environ.copy()
        annotated_skip_env["COMPFUZOR_CANONICAL_INSTALL_BYPASS"] = "1"
        annotated_skipped = run_script(output / "install.sh", annotated_skip_env)
        if body_output(annotated_skipped) != ["annotated-child"]:
            raise AssertionError(
                f"body skip suppressed annotated child: {annotated_skipped!r}"
            )
        require(
            annotated_skipped.stderr,
            "(canonical-author)",
            "annotated body report label",
        )

        pure = run_script(output / "apply.sh")
        if body_output(pure) != ["pure-child"]:
            raise AssertionError(f"pure compositor did not run child: {pure!r}")
        print("ok: canonical body guards are local and pure compositors stay unguarded")


if __name__ == "__main__":
    test_canonical_body_disarm_is_local_to_compositor_body()
