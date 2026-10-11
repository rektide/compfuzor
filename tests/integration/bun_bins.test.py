#!/usr/bin/env python3
"""Bun source builds select package scripts and preserve comment support."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile

import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = Path.home() / "tmp-opencode"


def render(tmp: Path, options: dict) -> tuple[Path, dict]:
    deploy = tmp / "payload"
    (deploy / "bin").mkdir(parents=True)
    (deploy / "repo").mkdir()
    variables = {
        "TYPE": "bun-test",
        "NAME": "bun-test",
        "DIR": str(deploy),
        "BINS_DIR": str(deploy / "bin"),
        "BUN": True,
        **options,
    }
    playbook = tmp / "render.pb"
    playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars: {json.dumps(variables)}
  tasks:
    - include_defaults:
        file: {str(ROOT / 'vars/common.yaml')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/gen_bun.tasks')!r}
    - ansible.builtin.import_tasks: {str(ROOT / 'tasks/compfuzor/gen_bins.tasks')!r}
    - ansible.builtin.template:
        src: {str(ROOT / 'files/_bin')!r}
        dest: "{{{{ BINS_DIR }}}}/{{{{ item.name }}}}"
        mode: '0755'
      loop: "{{{{ BINS }}}}"
    - ansible.builtin.copy:
        dest: {str(tmp / 'env.json')!r}
        content: "{{{{ ENV | to_json }}}}"
""")
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        cwd=ROOT,
        env=os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return deploy, json.loads((tmp / "env.json").read_text())


def execute(tmp: Path, deploy: Path, variables: dict, fail_script: str = "") -> tuple[int, list[str]]:
    stub = tmp / "stub"
    stub.mkdir(exist_ok=True)
    bun = stub / "bun"
    bun.write_text('''#!/bin/bash
printf '%s|%s\\n' "$PWD" "$*" >> "$BUN_TEST_LOG"
if [ "$*" = "run ${BUN_TEST_FAIL:-}" ]; then exit 23; fi
''')
    bun.chmod(0o755)
    log = tmp / "bun.log"
    log.unlink(missing_ok=True)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("BUN_", "BUILD_", "LINK_"))}
    env.update({
        **variables,
        "DIR": str(deploy),
        "PATH": f"{stub}:/usr/bin:/bin",
        "BUN_TEST_LOG": str(log),
        "BUN_TEST_FAIL": fail_script,
    })
    result = subprocess.run([str(deploy / "bin/build.sh")], cwd=tmp, env=env,
                            capture_output=True, text=True)
    lines = log.read_text().splitlines() if log.exists() else []
    assert all(line.split("|", 1)[0] == str(deploy / "repo") for line in lines)
    return result.returncode, [line.split("|", 1)[1] for line in lines]


def test_default_remains_install_only() -> None:
    for options in ({}, {"BUN_BUILD_SCRIPTS": []}):
        with tempfile.TemporaryDirectory(dir=SCRATCH, prefix="bun-bins-") as directory:
            tmp = Path(directory)
            deploy, variables = render(tmp, options)
            assert variables["BUN_BUILD_SCRIPTS"] == ""
            assert execute(tmp, deploy, variables) == (0, ["install"])


def test_selected_scripts_order_comments_and_failure() -> None:
    with tempfile.TemporaryDirectory(dir=SCRATCH, prefix="bun-bins-") as directory:
        tmp = Path(directory)
        deploy, variables = render(tmp, {
            "BUN_BUILD_SCRIPTS": ["web:build", "build:cli"],
            "BUN_BIN": "fixture",
            "BUN_COMMENT": ["Build web assets.", "Then build the CLI."],
            "BUN_COMMENT_INSTALL": "Link the source binaries.",
        })
        assert variables == {"BUN_BIN": "fixture", "BUN_BUILD_SCRIPTS": "web:build,build:cli"}
        build = (deploy / "bin/build-bun.sh").read_text()
        assert "# Build web assets.\n# Then build the CLI." in build
        install = (deploy / "bin/install-bun.sh").read_text()
        assert "# Link the source binaries." in install
        assert execute(tmp, deploy, variables) == (0, ["install", "run web:build", "run build:cli"])
        assert execute(tmp, deploy, variables, fail_script="web:build") == (23, ["install", "run web:build"])
        assert execute(tmp, deploy, variables | {"BUN_BUILD_SCRIPTS": "alternate"}) == (0, ["install", "run alternate"])


def test_scalar_scripts_and_comment() -> None:
    with tempfile.TemporaryDirectory(dir=SCRATCH, prefix="bun-bins-") as directory:
        tmp = Path(directory)
        deploy, variables = render(tmp, {
            "BUN_BUILD_SCRIPTS": "web:build,build:cli",
            "BUN_COMMENT": "Build the selected package scripts.",
        })
        assert "# Build the selected package scripts." in (deploy / "bin/build-bun.sh").read_text()
        assert execute(tmp, deploy, variables) == (0, ["install", "run web:build", "run build:cli"])


def test_motel_uses_shared_build_and_comments() -> None:
    options = yaml.safe_load((ROOT / "motel.src.pb").read_text())[0]["vars"]
    assert "BINS" not in options
    with tempfile.TemporaryDirectory(dir=SCRATCH, prefix="bun-bins-") as directory:
        tmp = Path(directory)
        deploy, variables = render(tmp, options)
        build = (deploy / "bin/build-bun.sh").read_text()
        assert "# prepublishOnly upstream: published @kitlangton/motel ships web/dist," in build
        assert "# which localServer.ts serves (WEB_DIST_DIR)." in build
        assert execute(tmp, deploy, variables) == (0, ["install", "run web:build"])


if __name__ == "__main__":
    test_default_remains_install_only()
    test_selected_scripts_order_comments_and_failure()
    test_scalar_scripts_and_comment()
    test_motel_uses_shared_build_and_comments()
    print("ok: bun package builds, environment overrides, comments, and motel integration")
