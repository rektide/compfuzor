#!/usr/bin/env python3
"""Exercise generated donor/config context tools against two scratch consumers."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "config-contexts"
NODE = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def runtime_env(home: Path, xdg: Path, temporary: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(xdg),
        "DIR": str(temporary / "foreign ambient deployment"),
        "TMPDIR": str(SCRATCH),
        "PATH": os.pathsep.join((str(Path(NODE).parent), "/usr/bin", "/bin")),
    })
    for name in ("COMPFUZOR_CONFIG_CONTEXTS_BYPASS", "COMPFUZOR_CONFIG_BYPASS", "COMPFUZOR_CONFIG_INSTALL_STRATEGY", "COMPFUZOR_CONFIG_DROPINS_STRATEGY"):
        env.pop(name, None)
    return env


def rows(result: subprocess.CompletedProcess[str]) -> list[dict]:
    return json.loads(result.stdout)


def test_config_context_toolkit() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="toolkit deployment with spaces-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "deployment"
        plan_file = temporary / "plan.json"
        playbook = temporary / "generate.pb"
        (temporary / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files: [{str(ROOT / 'vars' / 'common.yaml')!r}]
  vars:
    TYPE: config-toolkit-test
    NAME: config-toolkit-test
    DIR: {str(payload)!r}
    ETC: {str(payload / 'etc')!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    DIRS: []
    ETC_FILES: []
    STATUSES: []
    PKGS: []
    ENV: {{}}
    ENV_LIST: []
    LINKS:
      - id: shared-links-proof
        scope: user
        src: etc/outputs/main.conf
        dest: '${{HOME}}/.config/shared-links-proof.conf'
        policy: replace
    CONFIGS:
      outputs/main.conf:
        processor: concat
        validate: '! grep -q BROKEN "$CONFIG_CANDIDATE"'
        inputs:
          - file: inputs/base.conf
          - glob: inputs/main.d/*.conf
            name: main
          - glob: inputs/empty.d/*.conf
            name: empty
    CONFIG_CONTEXTS:
      user:
        scope: user
        root: config
        subpath: toolkit app
        install: assemble
        dropins: link
        configs: [main]
      system-test:
        scope: system
        root: {str(temporary / 'system consumer')!r}
        install: assemble
        dropins: link
        configs: [main]
  tasks:
    - set_fact:
        SUBSYSTEM: {{}}
        _ARTIFACTS: {{families: {{}}}}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'sub_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_config.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_links.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_bins.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
        mode: '0770'
      loop: "{{{{ DIRS + [ETC, BINS_DIR] }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/config.spec.json"
        content: "{{{{ SUBSYSTEM.config.spec | to_nice_json }}}}"
        mode: '0600'
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'link_plan.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins_link.tasks')!r}
    - copy:
        dest: {str(plan_file)!r}
        content: "{{{{ {{'bins': BINS, 'statuses': STATUSES, 'spec': SUBSYSTEM.config.spec}} | to_nice_json }}}}"
        mode: '0600'
""",
            encoding="utf-8",
        )
        ansible_env = os.environ.copy()
        ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", '{"TYPE":"config-toolkit-test","NAME":"config-toolkit-test"}'],
            cwd=ROOT,
            env=ansible_env,
        )

        plan = json.loads(plan_file.read_text(encoding="utf-8"))
        bins = {item["name"]: item for item in plan["bins"]}
        assert list(item["name"] for item in plan["bins"]).count("links/delivery.ts") == 1
        assert bins["install-user.sh"]["run_all"].count("install-config-user.sh") == 1
        assert not any(name in bins["install-user.sh"]["run_all"] for name in (
            "install-config-user-copy.sh", "install-config-user-link.sh",
            "install-config-user-dropins.sh", "install-config-user-dropins-copy.sh", "install-config-user-dropins-link.sh",
        ))
        assert "status-config-context-user.sh" in plan["statuses"]

        donor = payload / "etc" / "inputs" / "main.d"
        donor.mkdir(parents=True, exist_ok=True)
        donor_base = payload / "etc" / "inputs" / "base.conf"
        donor_base.write_text("base=one\n", encoding="utf-8")
        (donor / "10-linked.conf").write_text("linked=one\n", encoding="utf-8")
        (donor / "20-copied.conf").write_text("copied=one\n", encoding="utf-8")
        (donor / "30-disabled.conf.disabled").write_text("disabled=one\n", encoding="utf-8")
        canonical_env = os.environ.copy()
        canonical_env.pop("DIR", None)
        canonical_env["TMPDIR"] = str(SCRATCH)
        run([str(payload / "bin" / "config.sh"), "main"], cwd=payload, env=canonical_env)
        canonical_output = payload / "etc" / "outputs" / "main.conf"
        assert canonical_output.read_text(encoding="utf-8") == "base=one\nlinked=one\ncopied=one\n"

        home_one = temporary / "home one"
        xdg_one = temporary / "xdg one"
        env_one = runtime_env(home_one, xdg_one, temporary)
        local = xdg_one / "toolkit app"
        local_inputs = local / "inputs" / "main.d"
        local_output = local / "outputs" / "main.conf"
        install = payload / "bin" / "install-config-user.sh"
        dropins_copy = payload / "bin" / "install-config-user-dropins-copy.sh"
        dropins_link = payload / "bin" / "install-config-user-dropins-link.sh"
        inputs = payload / "bin" / "config-inputs-user.sh"
        config = payload / "bin" / "config-user.sh"
        status = payload / "bin" / "status-config-context-user.sh"

        run([str(payload / "bin" / "links.ts"), "apply", "--scope", "user", str(payload / "links.json")], cwd=temporary, env=env_one)
        assert (home_one / ".config" / "shared-links-proof.conf").is_symlink()

        run([str(install), "main"], cwd=temporary, env=env_one)
        assert (local / "inputs" / "base.conf").is_symlink()
        assert (local / "inputs" / "empty.d").is_dir()
        assert (local_inputs / "10-linked.conf").is_symlink()
        assert os.readlink(local_inputs / "10-linked.conf") == str(donor / "10-linked.conf")
        assert (local_inputs / "30-disabled.conf.disabled").is_symlink()
        assert not (local_inputs / "30-disabled.conf").exists()
        assert local_output.read_text(encoding="utf-8") == canonical_output.read_text(encoding="utf-8")

        run([str(dropins_copy), "main"], cwd=temporary, env=env_one)
        assert not (local / "inputs" / "base.conf").is_symlink()
        assert all(not (local_inputs / name).is_symlink() for name in ("10-linked.conf", "20-copied.conf", "30-disabled.conf.disabled"))
        run(
            [str(inputs), "put", "main/main", str(donor / "10-linked.conf"), "10-linked.conf", "--strategy", "link"],
            cwd=temporary,
            env=env_one,
        )
        mixed = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one)
        assert mixed.returncode == 0, mixed.stderr
        input_rows = {row["name"]: row for row in rows(mixed) if row["kind"] == "input"}
        assert input_rows["10-linked.conf"]["representation"] == "link"
        assert input_rows["20-copied.conf"]["representation"] == "copy"
        assert input_rows["30-disabled.conf"]["state"] == "disabled"
        assert all(row["status"] == "ok" for row in input_rows.values())
        input_only = run([str(inputs), "status", "main", "--json-array"], cwd=temporary, env=env_one)
        assert all(row["kind"] == "input" for row in rows(input_only))

        (local_inputs / "20-copied.conf").write_text("copied=local-edit\n", encoding="utf-8")
        (local_inputs / "90-local.conf").write_text("local=one\n", encoding="utf-8")
        run([str(config), "main"], cwd=temporary, env=env_one)
        local_assembled = local_output.read_bytes()
        run([str(install), "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").read_text(encoding="utf-8") == "copied=local-edit\n"
        assert (local_inputs / "90-local.conf").read_text(encoding="utf-8") == "local=one\n"
        assert local_output.read_bytes() == local_assembled
        edited_status = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert edited_status.returncode == 1
        edited_rows = rows(edited_status)
        assert next(row for row in edited_rows if row["kind"] == "input" and row["name"] == "20-copied.conf")["status"] == "modified"
        assert next(row for row in edited_rows if row["kind"] == "input" and row["name"] == "90-local.conf")["status"] == "local"
        assert next(row for row in edited_rows if row["kind"] == "output")["representation"] == "assembly"

        (donor / "10-linked.conf").write_text("linked=two\n", encoding="utf-8")
        (donor / "20-copied.conf").write_text("copied=two\n", encoding="utf-8")
        run([str(dropins_link), "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").is_symlink()
        assert (local_inputs / "30-disabled.conf.disabled").is_symlink()
        assert not (local_inputs / "30-disabled.conf").exists()
        assert (local_inputs / "90-local.conf").is_file()

        (local_inputs / "20-copied.conf").unlink()
        (local_inputs / "20-copied.conf").write_text("edited-without-force\n", encoding="utf-8")
        run([str(dropins_copy), "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").read_bytes() == (donor / "20-copied.conf").read_bytes()
        (local_inputs / "20-copied.conf").write_text("edited-again\n", encoding="utf-8")
        run([str(dropins_link), "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").is_symlink()

        (donor / "20-copied.conf").unlink()
        missing = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert missing.returncode == 2
        missing_row = next(row for row in rows(missing) if row["kind"] == "input" and row["name"] == "20-copied.conf")
        assert missing_row["status"] == "donor-missing"
        (donor / "20-copied.conf").write_text("copied=restored\n", encoding="utf-8")

        dangling_target = temporary / "missing producer.conf"
        (donor / "40-dangling.conf").symlink_to(dangling_target)
        run([str(dropins_link), "main"], cwd=temporary, env=env_one)
        dangling = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert dangling.returncode == 2
        dangling_row = next(row for row in rows(dangling) if row["kind"] == "input" and row["name"] == "40-dangling.conf")
        assert dangling_row["status"] == "donor-missing" and "dangling" in dangling_row["note"]
        run([str(inputs), "remove", "main/main", "40-dangling.conf"], cwd=temporary, env=env_one)
        (donor / "40-dangling.conf").unlink()

        run([str(inputs), "disable", "main/main", "10-linked.conf"], cwd=temporary, env=env_one)
        assert (local_inputs / "10-linked.conf.disabled").is_symlink()
        run([str(inputs), "enable", "main/main", "10-linked.conf"], cwd=temporary, env=env_one)
        assert (local_inputs / "10-linked.conf").is_symlink()

        broken = temporary / "50-broken.conf"
        broken.write_text("BROKEN=true\n", encoding="utf-8")
        failed_rebuild = run(
            [str(inputs), "put", "main/main", str(broken), "50-broken.conf", "--strategy", "copy"],
            cwd=temporary,
            env=env_one,
            check=False,
        )
        assert failed_rebuild.returncode == 4
        assert (local_inputs / "50-broken.conf").is_file()
        assert "input mutation remains" in failed_rebuild.stderr
        run([str(inputs), "remove", "main/main", "50-broken.conf"], cwd=temporary, env=env_one)

        removed_direct = run([str(inputs), "remove", "main/0"], cwd=temporary, env=env_one, check=False)
        assert removed_direct.returncode == 4 and not (local / "inputs" / "base.conf").exists()
        run([str(inputs), "put", "main/0", str(donor_base), "--strategy", "copy"], cwd=temporary, env=env_one)
        assert (local / "inputs" / "base.conf").read_bytes() == donor_base.read_bytes()

        run([str(payload / "bin" / "config.sh"), "main"], cwd=payload, env=canonical_env)
        run([str(payload / "bin" / "install-config-user-copy.sh"), "main"], cwd=temporary, env=env_one)
        assert not local_output.is_symlink() and local_output.read_bytes() == canonical_output.read_bytes()
        local_output.write_text("edited whole output\n", encoding="utf-8")
        run([str(payload / "bin" / "install-config-user-link.sh"), "main"], cwd=temporary, env=env_one)
        assert local_output.is_symlink() and os.readlink(local_output) == str(canonical_output)
        planned_detach = run([str(config), "--check", "main"], cwd=temporary, env=env_one, check=False)
        assert planned_detach.returncode == 1 and local_output.is_symlink()
        run([str(config), "main"], cwd=temporary, env=env_one)
        assert not local_output.is_symlink() and "local=one" in local_output.read_text(encoding="utf-8")
        assembled_status = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        output_row = next(row for row in rows(assembled_status) if row["kind"] == "output")
        assert output_row["status"] == "ok" and output_row["representation"] == "assembly"

        before_bypass = local_output.read_bytes()
        (local_inputs / "90-local.conf").write_text("local=bypass-change\n", encoding="utf-8")
        bypass_env = env_one | {"COMPFUZOR_CONFIG_CONTEXTS_BYPASS": "1"}
        skipped = run([str(install), "main"], cwd=temporary, env=bypass_env)
        assert "skipped" in skipped.stderr and local_output.read_bytes() == before_bypass

        sudo_shim = temporary / "sudo shim"
        sudo_shim.mkdir()
        sudo_log = temporary / "sudo.log"
        (sudo_shim / "sudo").write_text(f'#!/bin/sh\nprintf called >> {str(sudo_log)!r}\nexit 99\n', encoding="utf-8")
        (sudo_shim / "sudo").chmod(0o755)
        no_sudo_env = env_one | {
            "COMPFUZOR_LINKS_SUDO": "always",
            "PATH": os.pathsep.join((str(sudo_shim), str(Path(NODE).parent), "/usr/bin", "/bin")),
        }
        run([str(dropins_link), "main"], cwd=temporary, env=no_sudo_env)
        assert not sudo_log.exists()

        default_dropins = payload / "bin" / "install-config-user-dropins.sh"
        copy_default_env = env_one | {"COMPFUZOR_CONFIG_DROPINS_STRATEGY": "copy"}
        run([str(default_dropins), "main"], cwd=temporary, env=copy_default_env)
        assert not (local_inputs / "10-linked.conf").is_symlink()
        install_link_env = env_one | {"COMPFUZOR_CONFIG_INSTALL_STRATEGY": "link"}
        run([str(install), "main"], cwd=temporary, env=install_link_env)
        assert local_output.is_symlink() and os.readlink(local_output) == str(canonical_output)
        run([str(config), "main"], cwd=temporary, env=env_one)

        home_two = temporary / "home two"
        xdg_two = temporary / "second xdg root"
        env_two = runtime_env(home_two, xdg_two, temporary)
        run([str(install), "main"], cwd=temporary, env=env_two)
        local_two = xdg_two / "toolkit app"
        assert (local_two / "inputs" / "main.d" / "10-linked.conf").is_symlink()
        assert (local_two / "outputs" / "main.conf").is_file()
        assert (local_inputs / "90-local.conf").read_text(encoding="utf-8") == "local=bypass-change\n"

        run([str(payload / "bin" / "install-config-system-test.sh"), "main"], cwd=temporary, env=env_one)
        system_consumer = temporary / "system consumer"
        assert (system_consumer / "inputs" / "main.d" / "10-linked.conf").is_symlink()
        assert (system_consumer / "outputs" / "main.conf").is_file()

        listed = run([str(inputs), "list", "main"], cwd=temporary, env=env_one)
        assert "main/main" in listed.stdout and "main/0" in listed.stdout
        assert str(donor) in listed.stdout and str(local_inputs) in listed.stdout

        for module in (
            ROOT / "files" / "config" / "toolkit.ts",
            payload / "bin" / "config" / "toolkit.ts",
            ROOT / "files" / "links" / "delivery.ts",
            payload / "bin" / "links" / "delivery.ts",
        ):
            imported = run(
                [NODE, "--input-type=module", "--eval", f'import({json.dumps(module.as_uri())}).then(() => console.log("imported"))'],
                cwd=ROOT,
                env=env_one,
            )
            assert imported.stdout == "imported\n"

        duplicate_disabled = local_inputs / "10-linked.conf.disabled"
        duplicate_disabled.write_text("duplicate local state\n", encoding="utf-8")
        conflict_status = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert conflict_status.returncode == 1
        assert any(row["status"] == "local-conflict" and row["name"] == "10-linked.conf" for row in rows(conflict_status))
        conflict_refresh = run([str(dropins_link), "main"], cwd=temporary, env=env_one, check=False)
        assert conflict_refresh.returncode == 2
        assert (local_inputs / "10-linked.conf").exists() and duplicate_disabled.exists()
        duplicate_disabled.unlink()

        regular_input = local_inputs / "20-copied.conf"
        if regular_input.is_symlink() or regular_input.is_file():
            regular_input.unlink()
        regular_input.mkdir()
        rejected_directory = run([str(dropins_copy), "main"], cwd=temporary, env=env_one, check=False)
        assert rejected_directory.returncode == 2 and regular_input.is_dir()
        regular_input.rmdir()

        bypass_render = run(
            [
                "ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e",
                '{"TYPE":"config-toolkit-test","NAME":"config-toolkit-test","CONFIG_CONTEXTS_BYPASS":true}',
            ],
            cwd=ROOT,
            env=ansible_env,
        )
        assert bypass_render.returncode == 0
        bypass_plan = json.loads(plan_file.read_text(encoding="utf-8"))
        assert "contexts" not in bypass_plan["spec"]
        assert "config-user.sh" not in {item["name"] for item in bypass_plan["bins"]}


if __name__ == "__main__":
    test_config_context_toolkit()
    print("ok: config context donor toolkit")
