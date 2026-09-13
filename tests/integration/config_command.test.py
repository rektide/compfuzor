#!/usr/bin/env python3
"""Prove the fixed CONFIG multicall surface, selections, and precedence."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "config-command"


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def consumer_env(home: Path, context: str | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "TMPDIR": str(SCRATCH),
        "PATH": os.pathsep.join((str(Path(subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()).parent), "/usr/bin", "/bin")),
    })
    for name in (
        "COMPFUZOR_CONFIG_CONTEXT", "COMPFUZOR_CONTEXT",
        "COMPFUZOR_CONFIG_INSTALL_STRATEGY", "COMPFUZOR_CONFIG_DROPINS_STRATEGY",
        "COMPFUZOR_CONFIG_PUBLISH_STRATEGY",
    ):
        env.pop(name, None)
    if context is not None:
        env["COMPFUZOR_CONFIG_CONTEXT"] = context
    return env


def test_config_command() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="surface-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "deployment"
        system_root = temporary / "system context"
        plan_path = temporary / "plan.json"
        playbook = temporary / "generate.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files: [{str(ROOT / 'vars' / 'common.yaml')!r}]
  vars:
    TYPE: config-command-test
    NAME: config-command-test
    DIR: {str(payload)!r}
    ETC: {str(payload / 'etc')!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    DIRS: []
    ETC_FILES: []
    STATUSES: []
    PKGS: []
    CONFIGS:
      outputs/alpha.conf:
        processor: concat
        inputs: [{{file: inputs/alpha.conf}}]
      outputs/beta.conf:
        processor: concat
        inputs: [{{glob: inputs/beta.d/*.conf, name: beta}}]
      outputs/gamma.conf:
        processor: concat
        validate: '! grep -q BROKEN "$CONFIG_CANDIDATE"'
        inputs: [{{glob: inputs/gamma.d/*.conf, name: gamma}}]
    CONFIG_CONTEXTS:
      user:
        scope: user
        root: config
        subpath: command-test
        install: assemble
        dropins: link
      system:
        scope: system
        root: {str(system_root)!r}
        install: assemble
        dropins: copy
  tasks:
    - set_fact:
        SUBSYSTEM: {{}}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_bins.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
      loop: "{{{{ DIRS + [ETC, BINS_DIR] }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/config.spec.json"
        content: "{{{{ SUBSYSTEM.config.spec | to_nice_json }}}}"
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins_link.tasks')!r}
    - copy:
        dest: {str(plan_path)!r}
        content: "{{{{ {{'bins': BINS, 'spec': SUBSYSTEM.config.spec}} | to_nice_json }}}}"
""",
            encoding="utf-8",
        )
        ansible_env = os.environ.copy()
        ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        render = ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)]
        run(render, cwd=ROOT, env=ansible_env)

        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        bins = {item["name"]: item for item in plan["bins"]}
        fixed = {f"config-{action}.sh" for action in ("install", "assemble", "sync-inputs", "publish", "inputs", "status")}
        assert fixed.issubset(bins)
        assert all((payload / "bin" / name).is_symlink() for name in fixed)
        assert all((payload / "bin" / name).resolve() == payload / "bin" / "config" / "command.ts" for name in fixed)
        assert (payload / "bin" / "install.sh").read_text(encoding="utf-8").count('"$DIR/bin/config-install.sh" "$@"') == 1
        forbidden = ("config.sh", "config-context.sh", "config-user.sh", "config-system.sh")
        assert not any((payload / "bin" / name).exists() for name in forbidden)
        assert not any(name.startswith(("install-config-", "status-config-context-")) for name in bins)
        assert plan["spec"]["version"] == 2
        assert plan["spec"]["defaultContext"] == "user"
        assert plan["spec"]["contexts"]["canonical"]["canonical"] is True

        canonical = payload / "etc"
        (canonical / "inputs" / "alpha.conf").write_text("alpha=canonical\n", encoding="utf-8")
        (canonical / "inputs" / "beta.d" / "10.conf").write_text("beta=canonical\n", encoding="utf-8")
        (canonical / "inputs" / "gamma.d" / "10.conf").write_text("gamma=canonical\n", encoding="utf-8")
        base_env = consumer_env(temporary / "home")
        assemble = payload / "bin" / "config-assemble.sh"
        install = payload / "bin" / "config-install.sh"
        sync = payload / "bin" / "config-sync-inputs.sh"
        publish = payload / "bin" / "config-publish.sh"
        inputs = payload / "bin" / "config-inputs.sh"
        status = payload / "bin" / "config-status.sh"
        run([str(assemble), "--context", "canonical"], cwd=temporary, env=base_env)

        user_root = temporary / "home" / ".config" / "command-test"
        run([str(install)], cwd=temporary, env=base_env)
        assert all((user_root / "outputs" / f"{name}.conf").is_file() for name in ("alpha", "beta", "gamma"))
        (user_root / "outputs" / "gamma.conf").unlink()
        run([str(install), "alpha", "beta"], cwd=temporary, env=base_env)
        assert not (user_root / "outputs" / "gamma.conf").exists()
        run([str(install), "gamma"], cwd=temporary, env=base_env)

        multi_stdout = run([str(assemble), "--stdout", "alpha", "beta"], cwd=temporary, env=base_env, check=False)
        assert multi_stdout.returncode == 2 and "exactly one" in multi_stdout.stderr
        default_stdout = run([str(assemble), "--stdout"], cwd=temporary, env=base_env, check=False)
        assert default_stdout.returncode == 2 and "exactly one" in default_stdout.stderr

        # Zero, one, and multiple recipe selections work across the public actions.
        run([str(sync), "--strategy", "copy", "alpha", "gamma"], cwd=temporary, env=base_env)
        assert not (user_root / "inputs" / "alpha.conf").is_symlink()
        run([str(sync), "--strategy", "link", "beta"], cwd=temporary, env=base_env)
        assert (user_root / "inputs" / "beta.d" / "10.conf").is_symlink()
        run([str(sync), "--strategy", "link"], cwd=temporary, env=base_env)
        run([str(publish), "--strategy", "copy", "alpha", "gamma"], cwd=temporary, env=base_env)
        run([str(publish), "--strategy", "link", "beta"], cwd=temporary, env=base_env)
        assert (user_root / "outputs" / "beta.conf").is_symlink()
        run([str(publish), "--strategy", "copy"], cwd=temporary, env=base_env)
        run([str(assemble), "alpha", "beta"], cwd=temporary, env=base_env)
        assert not (user_root / "outputs" / "beta.conf").is_symlink()
        run([str(status), "alpha"], cwd=temporary, env=base_env)
        run([str(status), "alpha", "beta"], cwd=temporary, env=base_env)
        run([str(status)], cwd=temporary, env=base_env)
        listed = run([str(inputs), "list", "alpha", "gamma"], cwd=temporary, env=base_env)
        assert "alpha/0" in listed.stdout and "gamma/gamma" in listed.stdout and "beta/beta" not in listed.stdout
        assert "beta/beta" in run([str(inputs), "list"], cwd=temporary, env=base_env).stdout
        run([str(inputs), "status", "alpha", "gamma"], cwd=temporary, env=base_env)
        run([str(inputs), "status"], cwd=temporary, env=base_env)

        # The sole runner validates every selected candidate before committing any.
        alpha_output = user_root / "outputs" / "alpha.conf"
        alpha_before = alpha_output.read_bytes()
        (user_root / "inputs" / "alpha.conf").write_text("alpha=pending\n", encoding="utf-8")
        gamma_input = user_root / "inputs" / "gamma.d" / "10.conf"
        gamma_input.unlink()
        gamma_input.write_text("BROKEN\n", encoding="utf-8")
        rejected = run([str(assemble), "alpha", "gamma"], cwd=temporary, env=base_env, check=False)
        assert rejected.returncode == 1 and alpha_output.read_bytes() == alpha_before
        gamma_input.write_text("gamma=recovered\n", encoding="utf-8")
        run([str(assemble), "alpha", "gamma"], cwd=temporary, env=base_env)

        # Build a distinct system result for context/default/alias precedence.
        system_env = consumer_env(temporary / "irrelevant", "system")
        run([str(install)], cwd=temporary, env=system_env)
        (system_root / "inputs" / "alpha.conf").write_text("alpha=system\n", encoding="utf-8")
        run([str(assemble), "--context", "system", "alpha"], cwd=temporary, env=base_env)
        assert run([str(assemble), "--stdout", "alpha"], cwd=temporary, env=base_env).stdout == "alpha=pending\n"
        assert run([str(assemble), "--stdout", "alpha"], cwd=temporary, env=system_env).stdout == "alpha=system\n"
        generic_env = base_env | {"COMPFUZOR_CONTEXT": "system"}
        assert run([str(assemble), "--stdout", "alpha"], cwd=temporary, env=generic_env).stdout == "alpha=system\n"

        chain_alias = payload / "bin" / "config-system-assemble.sh"
        chain_alias.symlink_to("config-assemble.sh")
        direct_alias = payload / "bin" / "config-system-status.sh"
        direct_alias.symlink_to("config/command.ts")
        assert run([str(chain_alias), "--stdout", "alpha"], cwd=temporary, env=base_env).stdout == "alpha=system\n"
        conflicting_env = base_env | {"COMPFUZOR_CONFIG_CONTEXT": "system"}
        assert run([str(chain_alias), "--context", "user", "--stdout", "alpha"], cwd=temporary, env=conflicting_env).stdout == "alpha=pending\n"
        action_override = run([str(direct_alias), "--action", "assemble", "--stdout", "alpha"], cwd=temporary, env=base_env)
        assert action_override.stdout == "alpha=system\n"

        hostile_action = payload / "bin" / "config-system-hostile.sh"
        hostile_action.symlink_to("config/command.ts")
        assert run([str(hostile_action), "--action", "assemble", "--stdout", "alpha"], cwd=temporary, env=base_env).stdout == "alpha=system\n"
        hostile_context = payload / "bin" / "config-hostile-assemble.sh"
        hostile_context.symlink_to("config/command.ts")
        assert run([str(hostile_context), "--context", "system", "--stdout", "alpha"], cwd=temporary, env=base_env).stdout == "alpha=system\n"
        hostile = payload / "bin" / "not-a-config-command"
        hostile.symlink_to("config/command.ts")
        assert run([str(hostile)], cwd=temporary, env=base_env, check=False).returncode == 2
        assert run([str(hostile), "--action", "assemble", "--context", "system", "--stdout", "alpha"], cwd=temporary, env=base_env).stdout == "alpha=system\n"
        direct = payload / "bin" / "config" / "command.ts"
        assert run([str(direct), "--action", "assemble", "--context", "system", "--stdout", "alpha"], cwd=temporary, env=base_env).stdout == "alpha=system\n"

        # Strategy precedence is action-local; stale install settings do not poison status.
        strategy_home = temporary / "strategy home"
        strategy_env = consumer_env(strategy_home) | {
            "COMPFUZOR_CONFIG_INSTALL_STRATEGY": "copy",
            "COMPFUZOR_CONFIG_DROPINS_STRATEGY": "copy",
        }
        run([str(install), "alpha"], cwd=temporary, env=strategy_env)
        strategy_root = strategy_home / ".config" / "command-test"
        assert (strategy_root / "outputs" / "alpha.conf").is_file()
        assert not (strategy_root / "inputs" / "alpha.conf").exists()
        run([str(install), "--strategy", "assemble", "--dropins", "link", "alpha"], cwd=temporary, env=strategy_env)
        assert (strategy_root / "inputs" / "alpha.conf").is_symlink()
        copy_only_env = consumer_env(temporary / "copy-only home") | {
            "COMPFUZOR_CONFIG_INSTALL_STRATEGY": "copy",
            "COMPFUZOR_CONFIG_DROPINS_STRATEGY": "stale-unused",
        }
        run([str(install), "alpha"], cwd=temporary, env=copy_only_env)
        stale_env = base_env | {
            "COMPFUZOR_CONFIG_INSTALL_STRATEGY": "hostile",
            "COMPFUZOR_CONFIG_DROPINS_STRATEGY": "hostile",
        }
        stale_status = run([str(status), "alpha"], cwd=temporary, env=stale_env, check=False)
        assert stale_status.returncode != 2
        run([str(sync), "--strategy", "link", "alpha"], cwd=temporary, env=stale_env)

        canonical_rejection = run([str(sync), "--context", "canonical"], cwd=temporary, env=base_env, check=False)
        assert canonical_rejection.returncode == 2 and "not meaningful" in canonical_rejection.stderr

        # Global default and domain override flow through vars/common.yaml.
        run([*render, "-e", "CONTEXT_DEFAULT=system"], cwd=ROOT, env=ansible_env)
        assert json.loads(plan_path.read_text(encoding="utf-8"))["spec"]["defaultContext"] == "system"
        run([*render, "-e", "CONTEXT_DEFAULT=system", "-e", "CONFIG_CONTEXT=user"], cwd=ROOT, env=ansible_env)
        assert json.loads(plan_path.read_text(encoding="utf-8"))["spec"]["defaultContext"] == "user"


if __name__ == "__main__":
    test_config_command()
    print("ok: fixed config command surface")
