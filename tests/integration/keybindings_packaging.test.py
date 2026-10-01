#!/usr/bin/env python3
"""Package singular-domain YAML and external TS leaves using existing CONFIG tasks."""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/keybindings"


def test_packaging():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    readme = SCRATCH / "README.md"
    if not readme.exists():
        readme.write_text("# Keybinding scratch\n\nIsolated generated deployment fixtures only; no live compositor configuration.\n")
    with tempfile.TemporaryDirectory(prefix="packaging-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "deployment"
        etc = payload / "etc"
        playbook = temporary / "generate.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars_files: [{str(ROOT / 'vars/common.yaml')!r}]
  vars:
    TYPE: keybinding-test
    NAME: keybinding-test
    DIR: {str(payload)!r}
    ETC: {str(etc)!r}
    BINS_DIR: {str(payload / 'bin')!r}
    DIRSET: [etc]
    FILES: []
    DIRS: []
    STATUSES: []
    PKGS: []
    BINS:
      - name: keybinding-processor.mjs
        dest: keybinding-processor.mjs
        link: compfuzor-runtime.mjs
        compose: false
        basedir: false
    ETC_FILES:
      - name: action/launcher.yaml
        yaml:
          version: 1
          kind: action
          id: launcher
          exec: [vicinae, toggle]
      - name: keybinding/launch.yaml
        yaml:
          version: 1
          kind: keybinding
          id: launch
          action: launcher
          keys: [Mod+D]
          umbriel:
            keys: [Mod+Space]
    CONFIGS:
      niri/launch.binding.kdl:
        name: launch-niri-definition
        processor:
          command: keybinding-processor.mjs
          args: [--target, niri, --binding, launch, --material, definition]
        inputs: [{{file: action/launcher.yaml}}, {{file: keybinding/launch.yaml}}]
      niri/launch.include.kdl:
        name: launch-niri-include
        processor:
          command: keybinding-processor.mjs
          args: [--target, niri, --material, include]
        inputs: [{{file: niri/launch.binding.kdl}}]
      umbriel/launch.binding.toml:
        name: launch-umbriel-definition
        processor:
          command: keybinding-processor.mjs
          args: [--target, umbriel, --binding, launch, --material, definition]
        inputs: [{{file: action/launcher.yaml}}, {{file: keybinding/launch.yaml}}]
      umbriel/launch.include.toml.part:
        name: launch-umbriel-include
        processor:
          command: keybinding-processor.mjs
          args: [--target, umbriel, --material, include]
        inputs: [{{file: umbriel/launch.binding.toml}}]
  tasks:
    - set_fact:
        SUBSYSTEM: {{}}
    - import_tasks: {str(ROOT / 'tasks/compfuzor/sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks/compfuzor/gen_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks/compfuzor/compile_artifacts.tasks')!r}
    - file:
        path: {str(payload)!r}
        state: directory
    - import_tasks: {str(ROOT / 'tasks/compfuzor/fs_hierarchy.tasks')!r}
      vars:
        include: etc
    - file:
        path: "{{{{ item }}}}"
        state: directory
      loop: "{{{{ SUBSYSTEM.config.contrib.DIRS }}}}"
    - import_tasks: {str(ROOT / 'tasks/compfuzor/bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks/compfuzor/bins_link.tasks')!r}
""")
        env = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "TMPDIR": str(SCRATCH)}
        env.pop("DIR", None)
        result = subprocess.run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", '{"TYPE":"keybinding-test","NAME":"keybinding-test"}'], cwd=ROOT, env=env, text=True, capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert (etc / "action/launcher.yaml").is_file()
        assert (etc / "keybinding/launch.yaml").is_file()
        assembled = subprocess.run([str(payload / "bin/config-assemble.sh")], cwd=payload, env=env, text=True, capture_output=True)
        assert assembled.returncode == 0, assembled.stdout + assembled.stderr
        assert '"Mod+D"' in (etc / "niri/launch.binding.kdl").read_text()
        assert '"Mod+Space"' in (etc / "umbriel/launch.binding.toml").read_text()
        assert (etc / "niri/launch.include.kdl").read_text() == f'include "{etc}/niri/launch.binding.kdl"\n'
        assert (etc / "umbriel/launch.include.toml.part").read_text() == f'"{etc}/umbriel/launch.binding.toml",\n'
        print("ok: ETC_FILES.yaml packaging, generated external leaves and deployed TS processor")


if __name__ == "__main__":
    test_packaging()
