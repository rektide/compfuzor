#!/usr/bin/env python3
"""build-rust.sh treats links.mjs as an optional provider, not a dependency."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "rust-bins"


def run(*command: str, cwd: Path, env: dict[str, str] | None = None, check: bool = True) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, check=False)
    if check and result.returncode:
        raise AssertionError(f"{command} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def render_build_rust(tmp: Path) -> Path:
    deployment = tmp / "payload"
    repository = deployment / "repo"
    deployment.mkdir(parents=True, exist_ok=True)
    (deployment / "bin").mkdir(exist_ok=True)
    repository.mkdir(parents=True, exist_ok=True)
    (repository / "Cargo.toml").write_text("[package]\nname = 'fixture'\nversion = '0.0.0'\n")
    playbook = tmp / "render.pb"
    playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {str(ROOT / 'vars' / 'common.yaml')!r}
  vars:
    TYPE: opt
    NAME: fixture
    DIR: {str(deployment)!r}
    BINS_DIR: {str(deployment / 'bin')!r}
    REPO_DIR: {str(repository)!r}
    BINMODE: '0755'
    DEFAULT_HELPERS: [env, setopts, loud]
    RUST: true
    BINS: []
    ETC_FILES: []
    LINKS: []
  tasks:
    - ansible.builtin.set_fact:
        BINS: "{{{{ lookup('merge_subsys', id='rust', contrib='BINS') }}}}"
    - ansible.builtin.template:
        src: {str(ROOT / 'files/_bin')!r}
        dest: {str(deployment / 'bin/build-rust.sh')!r}
        mode: '0755'
      vars:
        item: "{{{{ BINS | selectattr('name', 'equalto', 'build-rust.sh') | first }}}}"
""")
    env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
    # -e outranks the vars_files load of common.yaml, whose own TYPE is
    # derived from the executing playbook's filename (/proc/self/cmdline).
    run("ansible-playbook", "-i", "localhost,", "-c", "local", "-e", "TYPE=opt",
        "-e", "NAME=fixture", str(playbook), cwd=ROOT, env=env)
    return deployment / "bin/build-rust.sh"


def stub_env(tmp: Path, deploy: Path) -> dict[str, str]:
    stub = tmp / "stub"
    stub.mkdir(exist_ok=True)
    (stub / "cargo").write_text('#!/bin/sh\nprintf "cargo:%s\\n" "$*" >> "$RUST_TEST_LOG"\n')
    (stub / "cargo").chmod(0o755)
    return os.environ | {"DIR": str(deploy), "RUST_TEST_LOG": str(tmp / "cargo.log"),
                         "PATH": f"{stub}:/usr/local/bin:/usr/bin:/bin"}


def test_build_rust_without_links_runtime_still_builds() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        script = render_build_rust(tmp)
        deploy = tmp / "payload"
        assert not (deploy / "bin/links.mjs").exists()
        env = stub_env(tmp, deploy)
        # A deployment with no LINKS artifacts ships no links.mjs; the build
        # must proceed instead of failing on the missing provider.
        run(str(script), cwd=tmp, env=env)
        assert (tmp / "cargo.log").read_text().splitlines() == ["cargo:build --release"]
        # When a link plan does provide links.mjs, the version-manager slice
        # is applied through it before cargo runs.
        (deploy / "bin/links.mjs").write_text(
            '#!/bin/sh\nprintf "links:%s\\n" "$*" >> "$RUST_TEST_LOG"\n')
        (deploy / "bin/links.mjs").chmod(0o755)
        (tmp / "cargo.log").unlink()
        run(str(script), cwd=tmp, env=env)
        assert (tmp / "cargo.log").read_text().splitlines() == [
            "links:apply --scope system --id */.tool-versions,*/mise.toml -q",
            "cargo:build --release",
        ]
