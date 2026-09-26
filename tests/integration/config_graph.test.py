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
          - glob: portable/*.json
            name: portable
            remote: true
            place: {{at: mcp.servers, as: object}}
            envsubst: {{file: ../env.export}}
          - glob: plugins/*.json
            name: plugins
            place: {{at: plugins, as: array}}
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
      loop: "{{{{ SUBSYSTEM.config.contrib.DIRS + [ETC, BINS_DIR, ETC + '/core', ETC + '/mcp', ETC + '/portable', ETC + '/plugins', ETC + '/shell.conf.d', ETC + '/policy.d'] }}}}"
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
        assert "disable-mcp.sh" not in plan["bins"]
        assert "disable-shell.conf.d.sh" not in plan["bins"]
        assert "config-inputs.sh" in plan["bins"]
        assert "config-remote.mjs" in plan["bins"]
        assert len([name for name in plan["bins"] if name.startswith("config-remote")]) == 1

        (payload / "etc" / "base.json").write_text('{"base": true, "mcp": {"servers": {"docs": {"type": "local", "command": ["stale"]}}}}\n')
        (payload / "etc" / "core" / "10-core.json").write_text('{"core": true}\n')
        (payload / "etc" / "mcp" / "10-server.json").write_text('{"mcp": {"legacy": true}}\n')
        producer = temporary / "producer"
        (producer / "etc").mkdir(parents=True)
        (producer / "env.export").write_text('export API_KEY=\'quoted"value\'\n', encoding="utf-8")
        (producer / "etc" / "mcp.json").write_text(
            '{"type":"remote","url":"https://example.test/mcp","headers":{"Authorization":"Bearer ${API_KEY}"}}\n',
            encoding="utf-8",
        )
        (payload / "etc" / "plugins" / "10-plugin.json").write_text('["one", "two"]\n')
        (payload / "etc" / "shell.conf.d" / "10-first.conf").write_text("first\n")
        (payload / "etc" / "shell.conf.d" / "20-second.conf").write_text("second\n")
        (payload / "etc" / "policy.d" / "10-policy.conf").write_text("policy=true\n")
        (payload / "etc" / "shell.conf").write_text("unmanaged\n# legacy-shell-old start\nstale\n# legacy-shell-old end\n")
        runtime_env = os.environ.copy()
        # This test invokes the deployment-local config leaf directly. Keep an
        # unrelated harness/developer DIR from selecting another deployment.
        runtime_env.pop("DIR", None)
        runtime_env["CONFIG_BLOCK_IN_FILE"] = str(block_fixture)

        # The generic remote manager links a portable producer record; the
        # filename, not its original basename, supplies the object slot.
        run([str(payload / "bin" / "config-remote.mjs"), "put", "portable", str(producer / "etc" / "mcp.json"), "docs.json"], cwd=payload, env=runtime_env)
        assert (payload / "etc" / "portable" / "docs.json").is_symlink()
        assert json.loads((payload / "etc" / "app.json").read_text())["mcp"]["servers"]["docs"]["headers"]["Authorization"] == 'Bearer quoted"value'
        assert "command" not in json.loads((payload / "etc" / "app.json").read_text())["mcp"]["servers"]["docs"]
        second = temporary / "second-producer"
        (second / "etc").mkdir(parents=True)
        (second / "env.export").write_text('export API_KEY=second\n', encoding="utf-8")
        (second / "etc" / "mcp.json").write_text('{"url":"${API_KEY}"}\n', encoding="utf-8")
        run([str(payload / "bin" / "config-remote.mjs"), "put", "portable", str(second / "etc" / "mcp.json"), "second.json"], cwd=payload, env=runtime_env)
        servers = json.loads((payload / "etc" / "app.json").read_text())["mcp"]["servers"]
        assert servers["second"]["url"] == "second"
        assert servers["docs"]["headers"]["Authorization"] == 'Bearer quoted"value'
        run([str(payload / "bin" / "config-remote.mjs"), "remove", "portable", "second.json"], cwd=payload, env=runtime_env)
        run([str(payload / "bin" / "config-remote.mjs"), "disable", "portable", "docs.json"], cwd=payload, env=runtime_env)
        assert (payload / "etc" / "portable" / "docs.json.disabled").is_symlink()
        assert json.loads((payload / "etc" / "app.json").read_text())["mcp"]["servers"]["docs"]["command"] == ["stale"]
        run([str(payload / "bin" / "config-remote.mjs"), "enable", "portable", "docs.json"], cwd=payload, env=runtime_env)

        listed = run([str(payload / "bin" / "config-assemble.sh"), "--list"], cwd=payload, env=runtime_env)
        assert listed.stdout.splitlines() == ["app", "policy", "shell"]
        run([str(payload / "bin" / "config-assemble.sh")], cwd=payload, env=runtime_env)
        assert json.loads((payload / "etc" / "app.json").read_text()) == {"base": True, "core": True, "mcp": {"legacy": True, "servers": {"docs": {"type": "remote", "url": "https://example.test/mcp", "headers": {"Authorization": 'Bearer quoted"value'}}}}, "plugins": ["one", "two"]}
        shell = (payload / "etc" / "shell.conf").read_text()
        assert "legacy-shell" not in shell and "unmanaged" in shell
        assert "shell/shell.conf.d/0/10-first.conf" in shell
        assert "shell/shell.conf.d/0/20-second.conf" in shell

        run(
            [
                str(payload / "bin" / "config-inputs.sh"),
                "--context",
                "canonical",
                "disable",
                "app/mcp",
                "10-server.json",
            ],
            cwd=payload,
            env=runtime_env,
        )
        assert (payload / "etc" / "mcp" / "10-server.json.disabled").exists()
        assert json.loads((payload / "etc" / "app.json").read_text())["mcp"]["servers"]["docs"]["type"] == "remote"

        original = (payload / "etc" / "app.json").read_text()
        (producer / "env.export").write_text('export API_KEY=changed\n', encoding="utf-8")
        drift = run([str(payload / "bin" / "config-assemble.sh"), "--check", "--quiet", "app"], cwd=payload, check=False, env=runtime_env)
        assert drift.returncode == 1 and (payload / "etc" / "app.json").read_text() == original
        (producer / "env.export").write_text('export API_KEY=\'quoted"value\'\n', encoding="utf-8")
        (producer / "etc" / "mcp.json").write_text('{"url":"${UNSET_PORTABLE_TEST_VAR}"}\n')
        failed = run([str(payload / "bin" / "config-assemble.sh"), "app"], cwd=payload, check=False, env=runtime_env)
        assert failed.returncode != 0 and "missing environment variable" in failed.stderr
        assert (payload / "etc" / "app.json").read_text() == original
        (producer / "etc" / "mcp.json").write_text('{"type":"local", "command":["echo"]}\n')
        (producer / "env.export").write_text('return 1\n', encoding="utf-8")
        failed = run([str(payload / "bin" / "config-assemble.sh"), "app"], cwd=payload, check=False, env=runtime_env)
        assert failed.returncode != 0 and "failed to load JSON input environment file" in failed.stderr
        assert (payload / "etc" / "app.json").read_text() == original
        (producer / "env.export").write_text('export API_KEY=\'quoted"value\'\n', encoding="utf-8")
        (payload / "etc" / "plugins" / "10-plugin.json").write_text('{"not": "an array"}\n')
        failed = run([str(payload / "bin" / "config-assemble.sh"), "app"], cwd=payload, check=False, env=runtime_env)
        assert failed.returncode != 0 and "expected JSON array" in failed.stderr
        assert (payload / "etc" / "app.json").read_text() == original
        (payload / "etc" / "plugins" / "10-plugin.json").write_text('["one", "two"]\n')
        (producer / "etc" / "mcp.json").write_text('{"x":1}\n{"y":2}\n')
        failed = run([str(payload / "bin" / "config-assemble.sh"), "app"], cwd=payload, check=False, env=runtime_env)
        assert failed.returncode != 0 and "exactly one JSON document" in failed.stderr
        assert (payload / "etc" / "app.json").read_text() == original

        (payload / "etc" / "policy.d" / "10-policy.conf").write_text("policy=false\n")
        (payload / "etc" / "core" / "10-core.json").write_text('{"core": false}\n')
        failed = run([str(payload / "bin" / "config-assemble.sh")], cwd=payload, check=False, env=runtime_env)
        assert failed.returncode == 1
        assert json.loads((payload / "etc" / "app.json").read_text())["core"] is True


if __name__ == "__main__":
    test_config_graph()
    print("ok: flat config integration")
