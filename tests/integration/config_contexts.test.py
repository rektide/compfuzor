#!/usr/bin/env python3
"""Render one reusable CONFIGS deployment and bind it to several consumers."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "config-contexts"
NODE = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()


def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def consumer_env(home: Path, block_fixture: Path, temporary: Path, *, xdg: Path | None = None) -> dict[str, str]:
    env = os.environ.copy()
    for name in ("XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "APP_PLAIN_FILE"):
        env.pop(name, None)
    env.update({
        "HOME": str(home),
        "DIR": str(temporary / "unrelated ambient deployment"),
        "TMPDIR": str(SCRATCH),
        "CONFIG_BLOCK_IN_FILE": str(block_fixture),
        # HOME is intentionally synthetic; avoid invoking the real user's mise
        # shims (notably jq) under that unrelated home.
        "PATH": os.pathsep.join((str(Path(NODE).parent), "/usr/bin", "/bin")),
    })
    if xdg is not None:
        env["XDG_CONFIG_HOME"] = str(xdg)
    return env


def seed_inputs(base: Path, *, plain: str, marker: str) -> None:
    (base / "inputs" / "plain.d").mkdir(parents=True)
    (base / "inputs" / "settings.d").mkdir(parents=True)
    (base / "inputs" / "shell.d").mkdir(parents=True)
    (base / "inputs" / "plain.d" / "10-main.conf").write_text(plain, encoding="utf-8")
    (base / "inputs" / "settings.d" / "10-main.json").write_text(
        json.dumps({"allow": True, "consumer": marker}) + "\n", encoding="utf-8"
    )
    (base / "inputs" / "shell.d" / "10-main.conf").write_text(f"{marker}=true\n", encoding="utf-8")


def test_config_contexts() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    readme = SCRATCH / "README.md"
    if not readme.exists():
        readme.write_text("# Config context test scratch\n", encoding="utf-8")

    with tempfile.TemporaryDirectory(prefix="rendered deployment with spaces-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "deployment payload"
        system_root = temporary / "explicit system context"
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
p.add_argument("--before"); p.add_argument("--after"); p.add_argument("--anchor")
a = p.parse_args(); output = Path(a.output)
text = output.read_text() if output.exists() else ""
blocks = re.compile(r"^# (.+) start\\n.*?^# \\1 end\\n?", re.MULTILINE | re.DOTALL)
if a.remove_match:
    owned = re.compile(a.remove_match)
    text = blocks.sub(lambda m: "" if owned.search(m.group(1)) else m.group(0), text)
else:
    body = Path(a.input).read_text()
    block = f"# {a.name} start\\n{body}# {a.name} end\\n"
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
    TYPE: config-context-test
    NAME: config-context-test
    DIR: {str(payload)!r}
    ETC: {str(payload / 'etc')!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    DIRS: []
    ETC_FILES: []
    STATUSES: []
    PKGS: []
    CONFIGS:
      outputs/plain.conf:
        processor: concat
        validate: 'grep -q "^valid=" "$CONFIG_CANDIDATE"'
        inputs: [{{glob: inputs/plain.d/*.conf}}]
      outputs/settings.json:
        processor: json-deep-merge
        validate: 'jq -e ".allow == true" "$CONFIG_CANDIDATE" >/dev/null'
        inputs: [{{glob: inputs/settings.d/*.json}}]
      outputs/shell.conf:
        processor: block-in-file
        block: {{after: EOF}}
        inputs: [{{glob: inputs/shell.d/*.conf}}]
      outputs/optional.conf:
        processor: concat
        apply: false
        inputs: [{{glob: inputs/optional.d/*.conf}}]
    CONFIG_CONTEXTS:
      user:
        scope: user
        root: config
        subpath: config-context-test
        configs:
          plain:
            output:
              env: APP_PLAIN_FILE
              default: outputs/plain.conf
          settings: {{}}
          shell: {{}}
          optional:
            output: {{env: REQUIRED_OUTPUT}}
      system-test:
        scope: system
        root: {str(system_root)!r}
        subpath: service
  tasks:
    - set_fact:
        SUBSYSTEM: {{}}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_config.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
        mode: '0770'
      loop: "{{{{ SUBSYSTEM.config.contrib.DIRS + [ETC, BINS_DIR] }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/config.spec.json"
        content: "{{{{ SUBSYSTEM.config.spec | to_nice_json }}}}"
        mode: '0600'
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins_link.tasks')!r}
    - copy:
        dest: {str(plan_file)!r}
        content: "{{{{ {{'bins': BINS | map(attribute='name') | list, 'spec': SUBSYSTEM.config.spec}} | to_nice_json }}}}"
        mode: '0600'
""",
            encoding="utf-8",
        )

        ansible_env = os.environ.copy()
        ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)], cwd=ROOT, env=ansible_env)

        plan = json.loads(plan_file.read_text(encoding="utf-8"))
        assert {"config/command.ts", "config/context.ts", "config-assemble.sh", "config-install.sh"}.issubset(plan["bins"])
        assert not {"config.sh", "config-context.sh", "config-user.sh", "config-system-test.sh"} & set(plan["bins"])
        assert plan["spec"]["contexts"]["user"]["scope"] == "user"
        assert plan["spec"]["contexts"]["system-test"]["root"] == {"path": str(system_root)}

        canonical = payload / "etc"
        (canonical / "inputs" / "plain.d" / "10-main.conf").write_text("valid=true\n", encoding="utf-8")
        (canonical / "inputs" / "settings.d" / "10-main.json").write_text('{"allow":true,"canonical":true}\n', encoding="utf-8")
        (canonical / "inputs" / "shell.d" / "10-main.conf").write_text("canonical=true\n", encoding="utf-8")
        canonical_shell = canonical / "outputs" / "shell.conf"
        canonical_shell.write_text("canonical unmanaged\n", encoding="utf-8")
        canonical_env = os.environ.copy()
        canonical_env["CONFIG_BLOCK_IN_FILE"] = str(block_fixture)
        canonical_env.pop("DIR", None)
        run([str(payload / "bin" / "config-assemble.sh"), "--context", "canonical"], cwd=payload, env=canonical_env)
        assert (canonical / "outputs" / "plain.conf").read_text(encoding="utf-8") == "valid=true\n"
        assert "canonical unmanaged" in canonical_shell.read_text(encoding="utf-8")

        home_one = temporary / "home one"
        base_one = home_one / ".config" / "config-context-test"
        seed_inputs(base_one, plain="valid=one\n", marker="home_one")
        env_one = consumer_env(home_one, block_fixture, temporary)
        user_command = payload / "bin" / "config-assemble.sh"

        listed = run([str(user_command), "--list"], cwd=temporary, env=env_one)
        assert listed.stdout.splitlines() == ["optional", "plain", "settings", "shell"]
        no_home_env = env_one.copy()
        no_home_env.pop("HOME")
        listed_without_home = run([str(user_command), "--list"], cwd=temporary, env=no_home_env)
        assert listed_without_home.stdout.splitlines() == ["optional", "plain", "settings", "shell"]
        streamed = run([str(user_command), "--stdout", "plain"], cwd=temporary, env=env_one)
        assert streamed.stdout == "valid=one\n"
        missing_check = run([str(user_command), "--check", "plain"], cwd=temporary, env=env_one, check=False)
        assert missing_check.returncode == 1 and "missing:" in missing_check.stdout
        assert not (base_one / "outputs").exists()

        run([str(user_command)], cwd=temporary, env=env_one)
        output_one = base_one / "outputs"
        assert (output_one / "plain.conf").read_text(encoding="utf-8") == "valid=one\n"
        assert json.loads((output_one / "settings.json").read_text(encoding="utf-8"))["consumer"] == "home_one"
        shell_one = (output_one / "shell.conf").read_text(encoding="utf-8")
        assert "home_one=true" in shell_one
        assert all((output_one / name).stat().st_mode & 0o777 == 0o600 for name in ("plain.conf", "settings.json", "shell.conf"))
        assert not (output_one / "optional.conf").exists()
        run([str(user_command), "settings"], cwd=temporary, env=env_one)
        run([str(user_command), "plain", "settings"], cwd=temporary, env=env_one)

        unchanged = (output_one / "plain.conf").stat()
        run([str(user_command)], cwd=temporary, env=env_one)
        unchanged_again = (output_one / "plain.conf").stat()
        assert (unchanged.st_ino, unchanged.st_mtime_ns) == (unchanged_again.st_ino, unchanged_again.st_mtime_ns)

        settings_output = output_one / "settings.json"
        settings_output.chmod(0o640)
        (base_one / "inputs" / "settings.d" / "10-main.json").write_text('{"allow":true,"consumer":"home_one-updated"}\n', encoding="utf-8")
        run([str(user_command), "settings"], cwd=temporary, env=env_one)
        assert settings_output.stat().st_mode & 0o777 == 0o640

        plain_output = output_one / "plain.conf"
        before_plain = plain_output.read_bytes()
        before_settings = settings_output.read_bytes()
        (base_one / "inputs" / "plain.d" / "10-main.conf").write_text("valid=pending\n", encoding="utf-8")
        (base_one / "inputs" / "settings.d" / "10-main.json").write_text('{"allow":false,"consumer":"rejected"}\n', encoding="utf-8")
        failed = run([str(user_command)], cwd=temporary, env=env_one, check=False)
        assert failed.returncode == 1 and "candidate validation failed" in failed.stderr
        assert plain_output.read_bytes() == before_plain
        assert settings_output.read_bytes() == before_settings

        (base_one / "inputs" / "plain.d" / "10-main.conf").write_text("valid=enumeration-pending\n", encoding="utf-8")
        missing_settings = base_one / "inputs" / "settings.d.missing"
        (base_one / "inputs" / "settings.d").rename(missing_settings)
        enumeration_failed = run([str(user_command)], cwd=temporary, env=env_one, check=False)
        assert enumeration_failed.returncode == 1
        assert "config input directory is missing" in enumeration_failed.stderr
        assert plain_output.read_bytes() == before_plain
        missing_settings.rename(base_one / "inputs" / "settings.d")

        (base_one / "inputs" / "plain.d" / "10-main.conf").write_text("valid=true\n", encoding="utf-8")
        (base_one / "inputs" / "settings.d" / "10-main.json").write_text('{"allow":true,"consumer":"home_one"}\n', encoding="utf-8")
        donor_plain = canonical / "outputs" / "plain.conf"
        plain_output.unlink()
        plain_output.symlink_to(donor_plain)
        donor_before = donor_plain.read_bytes()
        detach_check = run([str(user_command), "--check", "plain"], cwd=temporary, env=env_one, check=False)
        assert detach_check.returncode == 1 and "detach symlink:" in detach_check.stdout
        run([str(user_command), "plain"], cwd=temporary, env=env_one)
        assert not plain_output.is_symlink()
        assert plain_output.read_bytes() == donor_before == donor_plain.read_bytes()
        assert plain_output.stat().st_mode & 0o777 == 0o600

        home_two = temporary / "home two"
        xdg_two = temporary / "xdg config two"
        base_two = xdg_two / "config-context-test"
        seed_inputs(base_two, plain="valid=two\n", marker="home_two")
        env_two = consumer_env(home_two, block_fixture, temporary, xdg=xdg_two)
        custom_plain = home_two / "selected outputs" / "plain.conf"
        env_two["APP_PLAIN_FILE"] = str(custom_plain)
        run([str(user_command)], cwd=temporary, env=env_two)
        assert custom_plain.read_text(encoding="utf-8") == "valid=two\n"
        assert json.loads((base_two / "outputs" / "settings.json").read_text(encoding="utf-8"))["consumer"] == "home_two"
        assert plain_output.read_text(encoding="utf-8") == "valid=true\n"

        system_base = system_root / "service"
        seed_inputs(system_base, plain="valid=system\n", marker="system")
        system_env = consumer_env(home_one, block_fixture, temporary)
        system_command = payload / "bin" / "config-assemble.sh"
        run([str(system_command), "--context", "system-test"], cwd=temporary, env=system_env)
        assert (system_base / "outputs" / "plain.conf").read_text(encoding="utf-8") == "valid=system\n"

        deployed_direct = run(
            [str(payload / "bin" / "config" / "command.ts"), "--action", "assemble", "--context", "system-test", "--list"],
            cwd=temporary,
            env=system_env,
        )
        assert deployed_direct.stdout.splitlines() == ["optional", "plain", "settings", "shell"]
        source_direct = run(
            [
                NODE,
                str(ROOT / "files" / "config" / "command.ts"),
                "--action", "assemble",
                "--context",
                "system-test",
                "--spec",
                str(payload / "etc" / "config.spec.json"),
                "--runner",
                str(payload / "bin" / "config" / "run.sh"),
                "--list",
            ],
            cwd=ROOT,
            env=system_env,
        )
        assert source_direct.stdout.splitlines() == ["optional", "plain", "settings", "shell"]

        for module in (ROOT / "files" / "config" / "context.ts", payload / "bin" / "config" / "context.ts", ROOT / "files" / "config" / "command.ts"):
            imported = run(
                [NODE, "--input-type=module", "--eval", f'import({json.dumps(module.as_uri())}).then(() => console.log("imported"))'],
                cwd=ROOT,
                env=system_env,
            )
            assert imported.stdout == "imported\n"

        assert not list(temporary.rglob(".config-candidate.*"))
        assert not list(temporary.rglob(".config-backup.*"))


def test_context_signal_cleanup() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="signal cleanup-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        pid_file = temporary / "runner.pid"
        runner = temporary / "bin" / "config.sh"
        runner.parent.mkdir()
        runner.write_text(
            f'''#!/bin/bash
trap 'exit 143' TERM
printf '%s' "$$" > {str(pid_file)!r}
while true; do sleep 30 & wait "$!"; done
''',
            encoding="utf-8",
        )
        runner.chmod(0o755)
        spec = temporary / "config.spec.json"
        spec.write_text(json.dumps({
            "version": 2,
            "defaultContext": "test",
            "configs": {},
            "contexts": {"test": {"scope": "system", "root": {"path": str(temporary / "root")}, "configs": {}}},
        }), encoding="utf-8")
        env = os.environ.copy()
        env["TMPDIR"] = str(temporary)
        env["PATH"] = os.pathsep.join((str(Path(NODE).parent), "/usr/bin", "/bin"))
        process = subprocess.Popen(
            [NODE, str(ROOT / "files" / "config" / "command.ts"), "--action", "assemble", "--context", "test", "--spec", str(spec), "--runner", str(runner)],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        for _ in range(100):
            if pid_file.exists():
                break
            if process.poll() is not None:
                raise AssertionError(f"context runner exited before signal test: {process.communicate()}")
            time.sleep(0.02)
        else:
            process.kill()
            raise AssertionError("context runner did not start")
        child_pid = int(pid_file.read_text(encoding="utf-8"))
        process.terminate()
        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode == 143, (stdout, stderr)
        try:
            os.kill(child_pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError(f"mutating child remained alive after SIGTERM: {child_pid}")
        assert not list(temporary.glob("compfuzor-config-context-*"))


if __name__ == "__main__":
    test_config_contexts()
    test_context_signal_cleanup()
    print("ok: reusable config contexts")
