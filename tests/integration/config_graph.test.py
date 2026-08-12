#!/usr/bin/env python3
"""Exercise flat filename-keyed CONFIGS compilation and runtime."""

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
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def test_config_graph() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-config-") as tmp:
        temporary = Path(tmp)
        payload = temporary / "payload"
        plan_file = temporary / "plan.json"
        playbook = temporary / "generate.pb"
        block_fixture = temporary / "block-in-file"
        block_fixture.write_text(
            """#!/usr/bin/env python3
import argparse, re
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument("-n", "--name"); p.add_argument("-i", "--input")
p.add_argument("-o", "--output", required=True); p.add_argument("--remove-match")
p.add_argument("--before"); p.add_argument("--after")
a = p.parse_args(); output = Path(a.output)
text = output.read_text() if output.exists() else ""
blocks = re.compile(r"^# (.+) start\\n.*?^# \\1 end\\n?", re.MULTILINE | re.DOTALL)
if a.remove_match:
    owned = re.compile(a.remove_match)
    text = blocks.sub(lambda m: "" if owned.search(m.group(1)) else m.group(0), text)
else:
    block = f"# {a.name} start\\n{Path(a.input).read_text()}# {a.name} end\\n"
    text = block + text if a.before == "BOF" else text + block
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
  vars_files: [{str(ROOT / 'vars' / 'common.yaml')!r}]
  vars:
    TYPE: config-test
    NAME: config-test
    DIR: {str(payload)!r}
    ETC: {str(payload / 'etc')!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    DIRS: []
    ETC_FILES: []
    STATUSES: []
    PKGS: []
    CONFIGS:
      app.json:
        processor: json-deep-merge
        inputs:
          - file: base.json
          - glob: core/*.json
            name: core
          - glob: mcp/*.json
            name: mcp
            remote: true
      shell.conf:
        processor: block-in-file
        remote: true
        block:
          remove_match: ['^legacy-shell-']
      policy.conf:
        processor: concat
        disabled_suffix: false
        validate: 'grep -q "^policy=true$" "$CONFIG_CANDIDATE"'
        inputs: [{{glob: policy.d/*.conf}}]
  tasks:
    - set_fact:
        SUBSYSTEM: {{sentinel: {{spec: preserved}}}}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_config.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
        mode: '0770'
      loop: "{{{{ SUBSYSTEM.config.contrib.DIRS + [ETC, BINS_DIR, ETC + '/core', ETC + '/mcp', ETC + '/shell.conf.d', ETC + '/policy.d'] }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/config.spec.json"
        content: "{{{{ SUBSYSTEM.config.spec | to_nice_json }}}}"
        mode: '0660'
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins_link.tasks')!r}
    - copy:
        dest: {str(plan_file)!r}
        content: "{{{{ {{'bins': BINS | map(attribute='name') | list, 'statuses': STATUSES, 'spec': SUBSYSTEM.config.spec, 'sentinel': SUBSYSTEM.sentinel}} | to_nice_json }}}}"
""",
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)], cwd=ROOT, env=env)
        plan = json.loads(plan_file.read_text(encoding="utf-8"))
        assert plan["sentinel"]["spec"] == "preserved"
        assert set(plan["spec"]["configs"]) == {"app", "shell", "policy"}
        assert plan["spec"]["configs"]["shell"]["inputs"][0]["glob"].endswith("shell.conf.d/*.conf")
        assert plan["spec"]["remotes"]["shell.conf.d"]["config"] == "shell"
        assert "disable-mcp.sh" in plan["bins"]
        assert "disable-shell.conf.d.sh" in plan["bins"]

        (payload / "etc" / "base.json").write_text('{"base": true}\n')
        (payload / "etc" / "core" / "10-core.json").write_text('{"core": true}\n')
        (payload / "etc" / "mcp" / "10-server.json").write_text('{"mcp": true}\n')
        (payload / "etc" / "shell.conf.d" / "10-first.conf").write_text("first\n")
        (payload / "etc" / "shell.conf.d" / "20-second.conf").write_text("second\n")
        (payload / "etc" / "policy.d" / "10-policy.conf").write_text("policy=true\n")
        (payload / "etc" / "shell.conf").write_text("unmanaged\n# legacy-shell-old start\nstale\n# legacy-shell-old end\n")
        runtime_env = os.environ.copy()
        runtime_env["CONFIG_BLOCK_IN_FILE"] = str(block_fixture)

        listed = run([str(payload / "bin" / "config.sh"), "--list"], cwd=payload)
        assert listed.stdout.splitlines() == ["app", "policy", "shell"]
        run([str(payload / "bin" / "config.sh")], cwd=payload, env=runtime_env)
        assert json.loads((payload / "etc" / "app.json").read_text()) == {"base": True, "core": True, "mcp": True}
        shell = (payload / "etc" / "shell.conf").read_text()
        assert "legacy-shell" not in shell and "unmanaged" in shell
        assert "shell/shell.conf.d/0/10-first.conf" in shell
        assert "shell/shell.conf.d/0/20-second.conf" in shell

        run([str(payload / "bin" / "disable-mcp.sh"), "10-server"], cwd=payload)
        assert (payload / "etc" / "mcp" / "10-server.json.disabled").exists()
        assert json.loads((payload / "etc" / "app.json").read_text()) == {"base": True, "core": True}

        (payload / "etc" / "policy.d" / "10-policy.conf").write_text("policy=false\n")
        (payload / "etc" / "core" / "10-core.json").write_text('{"core": false}\n')
        failed = run([str(payload / "bin" / "config.sh")], cwd=payload, check=False, env=runtime_env)
        assert failed.returncode == 1
        assert json.loads((payload / "etc" / "app.json").read_text())["core"] is True


if __name__ == "__main__":
    test_config_graph()
    print("ok: flat config integration")
