#!/usr/bin/env python3
"""Exercise DROPINS + CONFIGS compilation, rendering, apply, status, and toggles."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], *, cwd: Path, check: bool = True, env=None) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=cwd, check=False, text=True, capture_output=True, env=env)
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
        block_fixture = temporary / "block-in-file"
        block_fixture.write_text(
            """#!/usr/bin/env python3
import argparse, re
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument("-n", "--name"); p.add_argument("-i", "--input")
p.add_argument("-o", "--output", required=True); p.add_argument("--remove-match")
p.add_argument("--before"); p.add_argument("--after"); p.add_argument("--anchor")
a = p.parse_args(); output = Path(a.output)
text = output.read_text() if output.exists() else ""
blocks = re.compile(r"^# (.+) start\\n.*?^# \\1 end\\n?", re.MULTILINE | re.DOTALL)
if a.remove_match:
    owned = re.compile(a.remove_match)
    text = blocks.sub(lambda m: "" if owned.search(m.group(1)) else m.group(0), text)
else:
    block = f"# {a.name} start\\n{Path(a.input).read_text()}# {a.name} end\\n"
    text = block + text if a.anchor and a.anchor.startswith("bof") else text + block
output.write_text(text)
""",
            encoding="utf-8",
        )
        block_fixture.chmod(0o755)
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
        root: "{{{{ ETC }}}}"
        path: core.d
        include: '*.json'
        disabled_suffix: .disabled
        files:
          - name: 10-core.json
            json: {{core: true}}
      app-mcp:
        root: "{{{{ ETC }}}}"
        path: mcp
        include: '*.json'
        disabled_suffix: .disabled
        files:
          - name: 10-server.json
            json: {{mcp: {{server: {{enabled: true}}}}}}
      policy:
        root: "{{{{ ETC }}}}"
        path: policy.d
        include: '*.conf'
        files:
          - name: 10-policy.conf
            content: "policy=true\\n"
      shell:
        root: "{{{{ ETC }}}}"
        path: shell.d
        include: '*.conf'
        disabled_suffix: .disabled
        files:
          - name: 20-second.conf
            content: "second\\n"
          - name: 10-first.conf
            content: "first\\n"
    CONFIGS:
      app:
        root: "{{{{ ETC }}}}"
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
        root: "{{{{ ETC }}}}"
        assemblies:
          main:
            output: policy.conf
            processor: concat
            validate: 'grep -q "^policy=true$" "$CONFIG_CANDIDATE"'
            inputs: [{{dropins: policy}}]
      shell:
        root: "{{{{ ETC }}}}"
        assemblies:
          main:
            output: shellrc
            processor: block-in-file
            block: {{namespace: test.shell, anchor: 'eof:100'}}
            inputs: [{{dropins: shell}}]
  tasks:
    - set_fact:
        SUBSYSTEM:
          sentinel:
            spec: preserved
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_config.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
        mode: '0770'
      loop: "{{{{ SUBSYSTEM.config.contrib.DIRS + [ETC, BINS_DIR] }}}}"
    - copy:
        dest: "{{{{ item.dest }}}}"
        content: "{{{{ item.json | to_nice_json if item.json is defined else item.content }}}}"
        mode: '0660'
      loop: "{{{{ SUBSYSTEM.config.contrib.ETC_FILES | selectattr('dest', 'defined') }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/base.json"
        content: '{{"base": true}}'
        mode: '0660'
    - copy:
        dest: "{{{{ ETC }}}}/config.spec.json"
        content: "{{{{ SUBSYSTEM.config.spec | to_nice_json }}}}"
        mode: '0660'
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins_link.tasks')!r}
    - copy:
        dest: {str(output)!r}
        content: "{{{{ {{'bins': BINS | map(attribute='name') | list, 'statuses': STATUSES, 'pkgs': PKGS, 'config_state': SUBSYSTEM.config, 'sentinel': SUBSYSTEM.sentinel}} | to_nice_json }}}}"
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
        assert plan["statuses"] == ["status-config-app.sh", "status-config-policy.sh", "status-config-shell.sh"]
        assert plan["pkgs"] == ["jq"]
        assert "disable-app.sh" in plan["bins"]
        assert "disable-policy.sh" not in plan["bins"]
        config_state = plan["config_state"]
        assert plan["sentinel"]["spec"] == "preserved"
        assert set(config_state["spec"]) == {"dropins", "configs"}
        assert config_state["spec"]["configs"]["app"]["order"] == ["mcp", "main"]
        assert config_state["contrib"]["DIRS"]
        assert any(item.get("name") == "config.spec.json" for item in config_state["contrib"]["ETC_FILES"])
        assert any(item["name"] == "config-app.sh" for item in config_state["contrib"]["BINS"])
        assert config_state["contrib"]["STATUSES"] == plan["statuses"]
        assert config_state["contrib"]["PKGS"] == plan["pkgs"]

        leaf = payload / "bin" / "internal" / "config" / "app" / "main"
        assert leaf.is_symlink()
        assert os.readlink(leaf) == str(payload / "bin" / "processors" / "json-deep-merge")
        listed = run([str(payload / "bin" / "config.sh"), "--list"], cwd=payload)
        listed_keys = [line for line in listed.stdout.splitlines() if "/" in line and not line.startswith("+")]
        assert listed_keys == ["app/mcp", "app/main", "policy/main", "shell/main"], (listed.stdout, listed.stderr)
        processor_user_call = run(
            [str(payload / "bin" / "processors" / "json-deep-merge"), "--list"],
            cwd=payload,
            check=False,
        )
        assert processor_user_call.returncode != 0
        assert "processors are internal" in processor_user_call.stderr

        shellrc = payload / "etc" / "shellrc"
        shellrc.write_text(
            "unmanaged\n# foreign/block start\nforeign\n# foreign/block end\n"
            "# test.shell/shell/obsolete start\nstale\n# test.shell/shell/obsolete end\n",
            encoding="utf-8",
        )
        runtime_env = os.environ.copy()
        runtime_env["CONFIG_BLOCK_IN_FILE"] = str(block_fixture)

        run([str(payload / "bin" / "config.sh")], cwd=payload, env=runtime_env)
        app = json.loads((payload / "etc" / "app.json").read_text(encoding="utf-8"))
        assert app == {"base": True, "core": True, "mcp": {"server": {"enabled": True}}}
        assert (payload / "etc" / "policy.conf").read_text(encoding="utf-8") == "policy=true\n"
        shell_text = shellrc.read_text(encoding="utf-8")
        assert "unmanaged\n" in shell_text and "foreign\n" in shell_text and "obsolete" not in shell_text
        assert shell_text.index("test.shell/shell/10-first") < shell_text.index("test.shell/shell/20-second")
        second = payload / "etc" / "shell.d" / "20-second.conf"
        second.rename(second.with_suffix(".conf.disabled"))
        run([str(payload / "bin" / "config.sh"), "shell/main"], cwd=payload, env=runtime_env)
        shell_text = shellrc.read_text(encoding="utf-8")
        assert "test.shell/shell/20-second" not in shell_text
        assert "unmanaged\n" in shell_text and "foreign\n" in shell_text

        (payload / "etc" / "policy.conf").unlink()
        (payload / "etc" / "mcp" / "10-server.json").write_text(
            '{"mcp": {"server": {"targeted": true}}}\n', encoding="utf-8"
        )
        run([str(payload / "bin" / "config.sh"), "app/main"], cwd=payload)
        assert not (payload / "etc" / "policy.conf").exists()
        assert json.loads((payload / "etc" / "app.json").read_text())["mcp"]["server"]["targeted"] is True
        (payload / "etc" / "mcp" / "10-server.json").write_text(
            '{"mcp": {"server": {"enabled": true}}}\n', encoding="utf-8"
        )
        run([str(payload / "bin" / "config-policy.sh")], cwd=payload)

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
        invalid = run([str(payload / "bin" / "config.sh")], cwd=payload, check=False, env=runtime_env)
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
