#!/usr/bin/env python3
"""Exercise DROPINS + CONFIGS compilation, rendering, apply, status, and toggles."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], *, cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=cwd, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}\n{result.stderr}"
        )
    return result


def test_config_graph() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-config-graph-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        output = temporary / "plan.json"
        playbook = temporary / "generate.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {str(ROOT / 'vars' / 'common.yaml')!r}
  vars:
    TYPE: config-graph-test
    NAME: config-graph-test
    DIR: {str(payload)!r}
    ETC: {str(payload / 'etc')!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    DIRS: []
    ETC_FILES: []
    STATUSES: []
    PKGS: []
    DROPINS:
      app-core:
        root: {str(payload / 'etc')!r}
        path: core.d
        include: '*.json'
        disabled_suffix: .disabled
        files:
          - name: 10-core.json
            json: {{core: true}}
      app-mcp:
        root: {str(payload / 'etc')!r}
        path: mcp
        include: '*.json'
        disabled_suffix: .disabled
        files:
          - name: 10-server.json
            json: {{mcp: {{server: {{enabled: true}}}}}}
      policy:
        root: {str(payload / 'etc')!r}
        path: policy.d
        include: '*.conf'
        files:
          - name: 10-policy.conf
            content: "policy=true\\n"
    CONFIGS:
      app:
        root: {str(payload / 'etc')!r}
        assemblies:
          mcp:
            output: generated/mcp.json
            processor: json-deep-merge
            inputs: [{{dropins: app-mcp}}]
          main:
            output: app.json
            processor: json-deep-merge
            inputs:
              - file: base.json
              - dropins: app-core
              - artifact: mcp
      policy:
        root: {str(payload / 'etc')!r}
        assemblies:
          main:
            output: policy.conf
            processor: concat
            validate: 'grep -q "^policy=true$" "$CONFIG_CANDIDATE"'
            inputs: [{{dropins: policy}}]
  tasks:
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_config.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
        mode: '0770'
      loop: "{{{{ _config_plan.dirs + [ETC, BINS_DIR] }}}}"
    - copy:
        dest: "{{{{ item.dest }}}}"
        content: "{{{{ item.json | to_nice_json if item.json is defined else item.content }}}}"
        mode: '0660'
      loop: "{{{{ _config_plan.files }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/base.json"
        content: '{{"base": true}}'
        mode: '0660'
    - copy:
        dest: "{{{{ ETC }}}}/config.spec.json"
        content: "{{{{ _config_plan.spec | to_nice_json }}}}"
        mode: '0660'
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - copy:
        dest: {str(output)!r}
        content: "{{{{ {{'bins': BINS | map(attribute='name') | list, 'statuses': STATUSES}} | to_nice_json }}}}"
        mode: '0600'
""",
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
        )

        plan = json.loads(output.read_text(encoding="utf-8"))
        assert plan["statuses"] == ["status-config-app.sh", "status-config-policy.sh"]
        assert "disable-app.sh" in plan["bins"]
        assert "disable-policy.sh" not in plan["bins"]

        run([str(payload / "bin" / "config.sh")], cwd=payload)
        app = json.loads((payload / "etc" / "app.json").read_text(encoding="utf-8"))
        assert app == {"base": True, "core": True, "mcp": {"server": {"enabled": True}}}
        assert (payload / "etc" / "policy.conf").read_text(encoding="utf-8") == "policy=true\n"

        app_output = payload / "etc" / "app.json"
        saved_app = payload / "etc" / "app.saved.json"
        app_output.rename(saved_app)
        app_output.mkdir()
        invalid_output = run([str(payload / "bin" / "config-app.sh")], cwd=payload, check=False)
        assert invalid_output.returncode == 1
        assert app_output.is_dir()
        app_output.rmdir()
        saved_app.rename(app_output)

        core = payload / "etc" / "core.d" / "10-core.json"
        core.write_text('{"core": false}\n', encoding="utf-8")
        policy_fragment = payload / "etc" / "policy.d" / "10-policy.conf"
        policy_fragment.write_text("policy=false\n", encoding="utf-8")
        invalid = run([str(payload / "bin" / "config.sh")], cwd=payload, check=False)
        assert invalid.returncode == 1
        assert json.loads((payload / "etc" / "app.json").read_text(encoding="utf-8"))["core"] is True
        assert (payload / "etc" / "policy.conf").read_text(encoding="utf-8") == "policy=true\n"
        policy_fragment.write_text("policy=true\n", encoding="utf-8")

        direct_status = run([str(payload / "bin" / "config-app.sh"), "--check", "-q"], cwd=payload, check=False)
        assert direct_status.returncode == 1, (direct_status.returncode, direct_status.stdout, direct_status.stderr)
        status = run([str(payload / "bin" / "status-config-app.sh"), "-q"], cwd=payload, check=False)
        assert status.returncode == 1, (
            status.returncode,
            status.stdout,
            status.stderr,
            (payload / "bin" / "status-config-app.sh").read_text(encoding="utf-8"),
        )
        assert json.loads((payload / "etc" / "app.json").read_text(encoding="utf-8"))["core"] is True

        duplicate = payload / "etc" / "mcp" / "10-core.json"
        duplicate.write_text("{}\n", encoding="utf-8")
        ambiguous = run([str(payload / "bin" / "disable-app.sh"), "10-core"], cwd=payload, check=False)
        assert ambiguous.returncode == 1
        assert core.is_file() and duplicate.is_file()
        duplicate.unlink()

        run(
            [str(payload / "bin" / "disable-app.sh"), "app-core:10-core", "app-core:10-core"],
            cwd=payload,
        )
        assert (payload / "etc" / "core.d" / "10-core.json.disabled").is_file()
        app = json.loads((payload / "etc" / "app.json").read_text(encoding="utf-8"))
        assert app == {"base": True, "mcp": {"server": {"enabled": True}}}

        disabled_core = payload / "etc" / "core.d" / "10-core.json.disabled"
        run([str(payload / "bin" / "enable-app.sh"), str(disabled_core)], cwd=payload)
        assert core.is_file()


if __name__ == "__main__":
    test_config_graph()
    print("ok: config graph integration")
