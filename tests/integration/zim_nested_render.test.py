#!/usr/bin/env python3
"""Real-Ansible proof that nested ZIM_MODULES declaration values render.

gen_zim.tasks must resolve template strings nested inside declaration
values (env/aliases/functions/arrays/source/args/comment) before they reach
the zim_fragment filter: ansible defers those strings, filter output is
never re-templated, and unrendered markers would install literally (the
live mise2 bug: `env: {MISE_CONFIG_DIR: "${MISE_CONFIG_DIR:-{{var}}}"}`
shipped `{{var}}` text). Renders a scratch playbook importing the real
gen_zim.tasks, lands ETC_FILES the way the producer fixtures do, and
asserts the generated init.zsh bodies arrive resolved -- including a value
mixing shell `${...}` expansion with a nested Jinja var.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "zim-nested-render"

PLAYBOOK_TEMPLATE = """---
- hosts: all
  gather_facts: false
  vars:
    TYPE: probe
    NAME: probe-main
    INSTANCE: main
    DIR: __PAYLOAD__
    ETC: __ETC__
    BINS_DIR: __BINS_DIR__
    BINS: []
    ETC_FILES: []
    ETC_DIRS: []
    DIRS: []
    ENV: {}
    ENV_LIST: []
    STATUSES: []
    ZIM_BYPASS: false
    # Declaration values mix shell expansion with nested Jinja references;
    # the space in the path also proves quoting survives the round trip.
    probe_config_dir: "$HOME/.config/probe dir/config"
    ENV:
      PROBE_PROMOTED: "${PROBE_PROMOTED:-{{probe_config_dir}}/promoted}"
    ZIM_ENV:
      - PROBE_PROMOTED
    ZIM_ARRAYS:
      fpath: ["{{probe_config_dir}}/functions"]
    ZIM_MODULES:
      - name: probe-env
        phase: 10
        channel: zimenv
        env:
          PROBE_CONFIG_DIR: "${PROBE_CONFIG_DIR:-{{probe_config_dir}}}"
          PROBE_PLAIN: "{{probe_config_dir}}/plain"
      - name: probe-aliases
        phase: 11
        aliases:
          pwhere: "echo {{probe_config_dir}}"
      # git-kind declaration with a template marker in source (the gmellon
      # shape: source: "{{DIR}}/zimfw") must also arrive resolved.
      - source: "{{ETC}}/vendor/probe-tool"
        phase: 12
  tasks:
    - import_tasks: __ROOT__/tasks/compfuzor/gen_zim.tasks
    - name: land generated tree for inspection
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
      loop: "{{ [ETC] + (ETC_DIRS | map('defaultDir', ETC) | list) }}"
    - name: land ETC_FILES verbatim for inspection
      ansible.builtin.copy:
        dest: "{{ item.name | defaultDir(ETC) }}"
        content: "{{ (item.json | to_nice_json) if item.json is defined else item.content }}"
      loop: "{{ ETC_FILES }}"
"""


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def render(payload: Path) -> Path:
    playbook_dir = payload.parent / "play"
    playbook_dir.mkdir(parents=True, exist_ok=True)
    playbook = playbook_dir / "probe.pb"
    playbook.write_text(
        PLAYBOOK_TEMPLATE.replace("__ROOT__", str(ROOT))
        .replace("__PAYLOAD__", str(payload))
        .replace("__ETC__", str(payload / "etc"))
        .replace("__BINS_DIR__", str(payload / "bin")),
        encoding="utf-8",
    )
    ansible_env = os.environ.copy()
    ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
    run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        cwd=ROOT,
        env=ansible_env,
    )
    return playbook


def test_zim_nested_declaration_values_render() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="zim nested render-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "deploy"
        render(payload)

        etc = payload / "etc"
        env_init = etc / "zim-modules" / "probe-env" / "init.zsh"
        alias_init = etc / "zim-modules" / "probe-aliases" / "init.zsh"
        assert env_init.is_file() and alias_init.is_file()

        body = env_init.read_text(encoding="utf-8")
        # the live bug shape: nested Jinja inside shell ${...} expansion
        assert (
            '_compfuzor_env_set PROBE_CONFIG_DIR "${PROBE_CONFIG_DIR:-$HOME/.config/probe dir/config}"'
            in body
        ), body
        assert '_compfuzor_env_set PROBE_PLAIN "$HOME/.config/probe dir/config/plain"' in body, body
        assert "{{" not in body and "{%" not in body, body

        aliases = alias_init.read_text(encoding="utf-8")
        assert "alias pwhere='echo $HOME/.config/probe dir/config'" in aliases, aliases
        assert "{{" not in aliases and "{%" not in aliases, aliases

        fragment = (etc / "zim" / "zimenv" / "active" / "10-probe-env.conf").read_text(encoding="utf-8")
        assert f"zmodule {etc}/zim-modules/probe-env\n" in fragment, fragment

        git_fragment = (etc / "zim" / "zimrc" / "active" / "12-probe-tool.conf").read_text(encoding="utf-8")
        assert f"zmodule {etc}/vendor/probe-tool\n" in git_fragment, git_fragment
        assert "{{" not in git_fragment, git_fragment

        # ZIM_ENV projection and ZIM_ARRAYS also route through `resolve`
        # inside gen_zim.tasks; their generated bodies must arrive resolved.
        env_module = etc / "zim-modules" / "probe-main-env" / "init.zsh"
        promoted = env_module.read_text(encoding="utf-8")
        assert (
            '_compfuzor_env_set PROBE_PROMOTED "${PROBE_PROMOTED:-$HOME/.config/probe dir/config/promoted}"'
            in promoted
        ), promoted
        assert "{{" not in promoted and "{%" not in promoted, promoted

        arrays = (etc / "zim-modules" / "probe-main-arrays" / "init.zsh").read_text(encoding="utf-8")
        assert (
            'typeset -a _compfuzor_array_values_0=("$HOME/.config/probe dir/config/functions")'
            in arrays
        ), arrays
        assert "{{" not in arrays and "{%" not in arrays, arrays

        # behavioral proof: sourcing the module exports the resolved default
        home = temporary / "shell home"
        probe = 'source "$1"; print -r -- "$PROBE_CONFIG_DIR|$PROBE_PLAIN"'
        selected = run(
            ["zsh", "-dfc", probe, "probe", str(env_init)],
            cwd=temporary,
            env={"HOME": str(home), "PATH": "/usr/bin:/bin"},
        )
        expected = f"{home}/.config/probe dir/config|{home}/.config/probe dir/config/plain"
        assert selected.stdout.strip() == expected, selected.stdout


if __name__ == "__main__":
    test_zim_nested_declaration_values_render()
    print("ok: zim nested declaration values render")
