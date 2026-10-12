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
          - glob: inputs/bracket.d/[ab][0-9].conf
            name: bracket
          - glob: inputs/wide.d/*
            name: wide
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
    - template:
        src: files/_bin
        dest: "{{{{ BINS_DIR }}}}/status.sh"
        mode: '0770'
      vars:
        item:
          name: status.sh
          basedir: false
          compose: false
          content: "{{{{ lookup('template', 'files/status/status.sh') }}}}"
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
        assert list(item["name"] for item in plan["bins"]).count("compfuzor-runtime.mjs") == 1
        assert list(item["name"] for item in plan["bins"]).count("links/links.mjs") == 1
        assert list(item["name"] for item in plan["bins"]).count("links.mjs") == 1
        assert not any(item["name"].endswith(".ts") for item in plan["bins"])
        assert bins["install.sh"]["run_all"].count("config-install.sh") == 1, bins["install.sh"]
        assert "config-install.sh" not in bins["install-user.sh"]["run_all"]
        assert {
            "id": "legacy:config-status.sh",
            "name": "config-status.sh",
            "exit2": "error",
            "contributors": ["deployment:config-toolkit-test", "subsystem:config"],
        } in plan["statuses"]
        fixed = {f"config-{action}.sh" for action in ("install", "assemble", "sync-inputs", "publish", "inputs", "status")}
        assert fixed.issubset(bins)
        assert all((payload / "bin" / name).is_symlink() for name in fixed)
        assert not any(name.startswith(("install-config-", "status-config-context-")) for name in bins)
        assert not any(name in {"config.sh", "config-context.sh"} for name in bins)
        assert (payload / "bin" / "status.sh").is_file()

        donor = payload / "etc" / "inputs" / "main.d"
        donor.mkdir(parents=True, exist_ok=True)
        donor_base = payload / "etc" / "inputs" / "base.conf"
        donor_base.write_text("base=one\n", encoding="utf-8")
        (donor / "10-linked.conf").write_text("linked=one\n", encoding="utf-8")
        (donor / "20-copied.conf").write_text("copied=one\n", encoding="utf-8")
        (donor / "30-disabled.conf.disabled").write_text("disabled=one\n", encoding="utf-8")
        bracket_donor = payload / "etc" / "inputs" / "bracket.d"
        (bracket_donor / "a1.conf").write_text("bracket=active\n", encoding="utf-8")
        (bracket_donor / "c1.conf").write_text("bracket=outside-pattern\n", encoding="utf-8")
        wide_donor = payload / "etc" / "inputs" / "wide.d"
        (wide_donor / ".hidden").write_text("wide=hidden\n", encoding="utf-8")
        (wide_donor / "active").write_text("wide=active\n", encoding="utf-8")
        (wide_donor / "disabled.disabled").write_text("wide=disabled\n", encoding="utf-8")
        canonical_env = os.environ.copy()
        canonical_env.pop("DIR", None)
        canonical_env["TMPDIR"] = str(SCRATCH)
        run([str(payload / "bin" / "config-assemble.sh"), "--context", "canonical", "main"], cwd=payload, env=canonical_env)
        canonical_output = payload / "etc" / "outputs" / "main.conf"
        assert canonical_output.read_text(encoding="utf-8") == "base=one\nlinked=one\ncopied=one\nbracket=active\nwide=hidden\nwide=active\n"

        home_one = temporary / "home one"
        xdg_one = temporary / "xdg one"
        env_one = runtime_env(home_one, xdg_one, temporary)
        local = xdg_one / "toolkit app"
        local_inputs = local / "inputs" / "main.d"
        local_output = local / "outputs" / "main.conf"
        install = payload / "bin" / "config-install.sh"
        sync_inputs = payload / "bin" / "config-sync-inputs.sh"
        inputs = payload / "bin" / "config-inputs.sh"
        config = payload / "bin" / "config-assemble.sh"
        status = payload / "bin" / "config-status.sh"
        publish = payload / "bin" / "config-publish.sh"
        raw_status = [str(payload / "bin" / "config" / "command.mjs"), "--action", "status", "--context", "user"]

        run([str(payload / "bin" / "links.mjs"), "apply", "--scope", "user", str(payload / "links.json")], cwd=temporary, env=env_one)
        assert (home_one / ".config" / "shared-links-proof.conf").is_symlink()

        run([str(install), "main"], cwd=temporary, env=env_one)
        assert (local / "inputs" / "base.conf").is_symlink()
        assert (local / "inputs" / "empty.d").is_dir()
        assert (local_inputs / "10-linked.conf").is_symlink()
        assert os.readlink(local_inputs / "10-linked.conf") == str(donor / "10-linked.conf")
        assert (local_inputs / "30-disabled.conf.disabled").is_symlink()
        assert not (local_inputs / "30-disabled.conf").exists()
        assert (local / "inputs" / "bracket.d" / "a1.conf").is_symlink()
        assert not (local / "inputs" / "bracket.d" / "c1.conf").exists()
        assert (local / "inputs" / "wide.d" / "active").is_symlink()
        assert (local / "inputs" / "wide.d" / ".hidden").is_symlink()
        assert (local / "inputs" / "wide.d" / "disabled.disabled").is_symlink()
        assert "wide=disabled" not in local_output.read_text(encoding="utf-8")
        assert local_output.read_text(encoding="utf-8") == canonical_output.read_text(encoding="utf-8")

        bracket_local = temporary / "bracket-local.conf"
        bracket_local.write_text("bracket=local\n", encoding="utf-8")
        invalid_bracket = run(
            [str(inputs), "put", "main/bracket", str(bracket_local), "c2.conf", "--strategy", "copy"],
            cwd=temporary,
            env=env_one,
            check=False,
        )
        assert invalid_bracket.returncode == 2 and not (local / "inputs" / "bracket.d" / "c2.conf").exists()
        run(
            [str(inputs), "put", "main/bracket", str(bracket_local), "b2.conf", "--strategy", "copy"],
            cwd=temporary,
            env=env_one,
        )
        assert (local / "inputs" / "bracket.d" / "b2.conf").is_file()

        run([str(sync_inputs), "--strategy", "copy", "main"], cwd=temporary, env=env_one)
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
        assert input_rows["b2.conf"]["status"] == "local"
        assert all(input_rows[name]["status"] == "ok" for name in ("10-linked.conf", "20-copied.conf", "30-disabled.conf", "a1.conf", "active", "disabled"))
        input_only = run([str(inputs), "status", "main", "--json-array"], cwd=temporary, env=env_one)
        assert all(row["kind"] == "input" for row in rows(input_only))

        producer = temporary / "linked producer.conf"
        producer.write_bytes((donor / "10-linked.conf").read_bytes())
        (donor / "10-linked.conf").unlink()
        (donor / "10-linked.conf").symlink_to(producer)
        local_link = local_inputs / "10-linked.conf"
        alias_parent = temporary / "producer alias"
        alias_parent.symlink_to(temporary, target_is_directory=True)
        for target in (producer, Path(os.path.relpath(producer, local_inputs)), alias_parent / producer.name):
            local_link.unlink()
            local_link.symlink_to(target)
            equivalent = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one)
            equivalent_row = next(row for row in rows(equivalent) if row["kind"] == "input" and row["name"] == "10-linked.conf")
            assert equivalent_row["status"] == "ok" and equivalent_row["representation"] == "link"

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
        run([str(sync_inputs), "--strategy", "link", "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").is_symlink()
        assert (local_inputs / "30-disabled.conf.disabled").is_symlink()
        assert not (local_inputs / "30-disabled.conf").exists()
        assert (local_inputs / "90-local.conf").is_file()

        (local_inputs / "20-copied.conf").unlink()
        (local_inputs / "20-copied.conf").write_text("edited-without-force\n", encoding="utf-8")
        run([str(sync_inputs), "--strategy", "copy", "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").read_bytes() == (donor / "20-copied.conf").read_bytes()
        (local_inputs / "20-copied.conf").write_text("edited-again\n", encoding="utf-8")
        run([str(sync_inputs), "--strategy", "link", "main"], cwd=temporary, env=env_one)
        assert (local_inputs / "20-copied.conf").is_symlink()

        (donor / "20-copied.conf").unlink()
        missing = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert missing.returncode == 2
        missing_row = next(row for row in rows(missing) if row["kind"] == "input" and row["name"] == "20-copied.conf")
        assert missing_row["status"] == "donor-missing"
        missing_raw = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert missing_raw.returncode == 2
        (donor / "20-copied.conf").write_text("copied=restored\n", encoding="utf-8")

        dangling_target = temporary / "missing producer.conf"
        (donor / "40-dangling.conf").symlink_to(dangling_target)
        run([str(sync_inputs), "--strategy", "link", "main"], cwd=temporary, env=env_one)
        dangling = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert dangling.returncode == 2
        dangling_row = next(row for row in rows(dangling) if row["kind"] == "input" and row["name"] == "40-dangling.conf")
        assert dangling_row["status"] == "donor-missing" and "dangling" in dangling_row["note"]
        dangling_raw = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert dangling_raw.returncode == 2
        aggregate = run([str(payload / "bin" / "status.sh")], cwd=temporary, env=env_one | {"DIR": str(payload)}, check=False)
        assert aggregate.returncode == 1 and "config-status.sh" in aggregate.stdout
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
        validation_status = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert validation_status.returncode == 2
        validation_rows = rows(validation_status)
        validation_error = next(row for row in validation_rows if row["kind"] == "assembly")
        assert validation_error["status"] == "evaluation-error" and "candidate validation failed" in validation_error["note"]
        assert next(row for row in validation_rows if row["kind"] == "output")["status"] != "modified"
        run([str(inputs), "remove", "main/main", "50-broken.conf"], cwd=temporary, env=env_one)

        leaf = payload / "bin" / "internal" / "config" / "main"
        hidden_leaf = payload / "bin" / "internal" / "config" / "main.hidden"
        leaf.rename(hidden_leaf)
        unavailable_status = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        hidden_leaf.rename(leaf)
        assert unavailable_status.returncode == 2
        unavailable_error = next(row for row in rows(unavailable_status) if row["kind"] == "assembly")
        assert "missing config leaf" in unavailable_error["note"]

        run([str(sync_inputs), "--strategy", "copy", "main"], cwd=temporary, env=env_one)
        if os.geteuid() != 0:
            donor_copy = donor / "20-copied.conf"
            donor_copy.chmod(0)
            unreadable_status = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
            donor_copy.chmod(0o644)
            assert unreadable_status.returncode == 2
            unreadable_row = next(row for row in rows(unreadable_status) if row["kind"] == "input" and row["name"] == "20-copied.conf")
            assert unreadable_row["status"] == "evaluation-error" and "cannot compare" in unreadable_row["note"]

        removed_direct = run([str(inputs), "remove", "main/0"], cwd=temporary, env=env_one, check=False)
        assert removed_direct.returncode == 4 and not (local / "inputs" / "base.conf").exists()
        run([str(inputs), "put", "main/0", str(donor_base), "--strategy", "copy"], cwd=temporary, env=env_one)
        assert (local / "inputs" / "base.conf").read_bytes() == donor_base.read_bytes()

        run([str(payload / "bin" / "config-assemble.sh"), "--context", "canonical", "main"], cwd=payload, env=canonical_env)
        run([str(publish), "--strategy", "copy", "main"], cwd=temporary, env=env_one)
        assert not local_output.is_symlink() and local_output.read_bytes() == canonical_output.read_bytes()
        local_output.write_text("edited whole output\n", encoding="utf-8")
        run([str(publish), "--strategy", "link", "main"], cwd=temporary, env=env_one)
        assert local_output.is_symlink() and os.readlink(local_output) == str(canonical_output)
        canonical_alias = temporary / "canonical output alias"
        canonical_alias.symlink_to(canonical_output.parent, target_is_directory=True)
        local_output.unlink()
        local_output.symlink_to(canonical_alias / canonical_output.name)
        equivalent_output = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        equivalent_output_row = next(row for row in rows(equivalent_output) if row["kind"] == "output")
        assert equivalent_output_row["status"] == "ok" and equivalent_output_row["representation"] == "link"
        planned_detach = run([str(config), "--check", "main"], cwd=temporary, env=env_one, check=False)
        assert planned_detach.returncode == 1 and local_output.is_symlink()
        run([str(config), "main"], cwd=temporary, env=env_one)
        assert not local_output.is_symlink() and "local=one" in local_output.read_text(encoding="utf-8")
        assembled_status = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        output_row = next(row for row in rows(assembled_status) if row["kind"] == "output")
        assert output_row["status"] == "ok" and output_row["representation"] == "assembly"

        canonical_output.unlink()
        without_canonical = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert without_canonical.returncode == 0
        without_canonical_rows = rows(without_canonical)
        local_health = next(row for row in without_canonical_rows if row["kind"] == "output")
        assert local_health["status"] == "ok" and local_health["representation"] == "assembly"
        assert "canonical output unavailable" in local_health["note"]
        assert next(row for row in without_canonical_rows if row["kind"] == "assembly")["status"] == "ready"
        unavailable_whole = run(
            [str(publish), "--strategy", "copy", "main"],
            cwd=temporary,
            env=env_one,
            check=False,
        )
        assert unavailable_whole.returncode == 2
        run([str(payload / "bin" / "config-assemble.sh"), "--context", "canonical", "main"], cwd=payload, env=canonical_env)

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
        run([str(sync_inputs), "--strategy", "link", "main"], cwd=temporary, env=no_sudo_env)
        assert not sudo_log.exists()

        copy_default_env = env_one | {"COMPFUZOR_CONFIG_DROPINS_STRATEGY": "copy"}
        run([str(sync_inputs), "main"], cwd=temporary, env=copy_default_env)
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

        home_whole = temporary / "whole-only home"
        xdg_whole = temporary / "whole-only xdg"
        env_whole = runtime_env(home_whole, xdg_whole, temporary)
        run([str(publish), "--strategy", "copy", "main"], cwd=temporary, env=env_whole)
        whole_only = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_whole, check=False)
        assert whole_only.returncode == 0
        whole_only_rows = rows(whole_only)
        assert next(row for row in whole_only_rows if row["kind"] == "output")["status"] == "ok"
        assert next(row for row in whole_only_rows if row["kind"] == "assembly")["status"] == "inactive"
        assert all(row["status"] == "inactive" for row in whole_only_rows if row["kind"] == "input")
        whole_inputs = run([str(inputs), "status", "main", "--json-array"], cwd=temporary, env=env_whole, check=False)
        assert whole_inputs.returncode == 1 and any(row["status"] == "missing" for row in rows(whole_inputs))
        whole_check = run([str(config), "--check", "main"], cwd=temporary, env=env_whole, check=False)
        assert whole_check.returncode != 0
        run([str(publish), "--strategy", "link", "main"], cwd=temporary, env=env_whole)
        whole_link_status = run([*raw_status, "main", "--json-array"], cwd=temporary, env=env_whole)
        assert next(row for row in rows(whole_link_status) if row["kind"] == "output")["representation"] == "link"

        run([str(install), "--context", "system-test", "main"], cwd=temporary, env=env_one)
        system_consumer = temporary / "system consumer"
        assert (system_consumer / "inputs" / "main.d" / "10-linked.conf").is_symlink()
        assert (system_consumer / "outputs" / "main.conf").is_file()

        listed = run([str(inputs), "list", "main"], cwd=temporary, env=env_one)
        assert "main/main" in listed.stdout and "main/0" in listed.stdout
        assert str(donor) in listed.stdout and str(local_inputs) in listed.stdout

        for module in (
            ROOT / "build" / "runtime" / "compfuzor-runtime.mjs",
            payload / "bin" / "config" / "command.mjs",
            ROOT / "files" / "links" / "delivery.ts",
        ):
            imported = run(
                [NODE, "--input-type=module", "--eval", f'import({json.dumps(module.as_uri())}).then(() => console.log("imported"))'],
                cwd=ROOT,
                env=env_one,
            )
            assert imported.stdout == "imported\n"

        missing_extra = local_inputs / "91-dangling.conf.disabled"
        missing_extra.symlink_to(temporary / "missing local extra.conf")
        directory_target = temporary / "extra directory"
        directory_target.mkdir()
        directory_extra = local_inputs / "92-directory.conf"
        directory_extra.symlink_to(directory_target, target_is_directory=True)
        producer_chain = temporary / "producer-chain.conf"
        producer_chain.symlink_to(temporary / "missing producer target.conf")
        chain_extra = local_inputs / "93-chain.conf"
        chain_extra.symlink_to(producer_chain)
        weird_status = run([str(inputs), "status", "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert weird_status.returncode == 2
        weird_rows = {row["name"]: row for row in rows(weird_status)}
        assert weird_rows["91-dangling.conf"]["status"] == "dangling" and weird_rows["91-dangling.conf"]["state"] == "disabled"
        assert weird_rows["92-directory.conf"]["status"] == "non-file-referent"
        assert weird_rows["93-chain.conf"]["status"] == "dangling"
        missing_extra.unlink()
        directory_extra.unlink()
        chain_extra.unlink()
        producer_chain.unlink()

        hazard_home = temporary / "hazard home"
        hazard_xdg = temporary / "hazard xdg"
        hazard_env = runtime_env(hazard_home, hazard_xdg, temporary)
        hazard_root = hazard_xdg / "toolkit app"
        hazard_root.mkdir(parents=True)
        (hazard_root / "inputs").symlink_to(payload / "etc" / "inputs", target_is_directory=True)
        (hazard_root / "outputs").symlink_to(payload / "etc" / "outputs", target_is_directory=True)
        donor_snapshot = {path.name: path.read_bytes() for path in donor.iterdir() if path.is_file()}
        donor_output_snapshot = (payload / "etc" / "outputs" / "main.conf").read_bytes()
        custom_hazard = temporary / "99-custom.conf"
        custom_hazard.write_text("custom=hazard\n", encoding="utf-8")
        hazard_put = run(
            [str(inputs), "put", "main/main", str(custom_hazard), "99-custom.conf", "--no-rebuild"],
            cwd=temporary,
            env=hazard_env,
            check=False,
        )
        hazard_toggle = run([str(inputs), "disable", "main/main", "10-linked.conf"], cwd=temporary, env=hazard_env, check=False)
        hazard_remove = run([str(inputs), "remove", "main/main", "10-linked.conf"], cwd=temporary, env=hazard_env, check=False)
        hazard_direct = run([str(inputs), "put", "main/0", str(custom_hazard), "--no-rebuild"], cwd=temporary, env=hazard_env, check=False)
        assert {hazard_put.returncode, hazard_toggle.returncode, hazard_remove.returncode, hazard_direct.returncode} == {2}
        assert not (donor / "99-custom.conf").exists()
        assert {path.name: path.read_bytes() for path in donor.iterdir() if path.is_file()} == donor_snapshot
        hazard_assembly = run([str(config), "main"], cwd=temporary, env=hazard_env, check=False)
        assert hazard_assembly.returncode == 2
        assert (payload / "etc" / "outputs" / "main.conf").read_bytes() == donor_output_snapshot
        hazard_preview = run([str(config), "--check", "main"], cwd=temporary, env=hazard_env, check=False)
        assert "aliases canonical output" not in hazard_preview.stderr
        hazard_status = run([*raw_status, "main", "--json-array"], cwd=temporary, env=hazard_env, check=False)
        assert hazard_status.returncode == 2
        assert any(row["status"] == "alias-hazard" and row["kind"] == "output" for row in rows(hazard_status))
        assert any(row["status"] == "alias-hazard" and row["kind"] == "input" for row in rows(hazard_status))

        duplicate_disabled = local_inputs / "10-linked.conf.disabled"
        duplicate_disabled.write_text("duplicate local state\n", encoding="utf-8")
        conflict_status = run([str(status), "main", "--json-array"], cwd=temporary, env=env_one, check=False)
        assert conflict_status.returncode == 1
        assert any(row["status"] == "local-conflict" and row["name"] == "10-linked.conf" for row in rows(conflict_status))
        conflict_refresh = run([str(sync_inputs), "--strategy", "link", "main"], cwd=temporary, env=env_one, check=False)
        assert conflict_refresh.returncode == 2
        assert (local_inputs / "10-linked.conf").exists() and duplicate_disabled.exists()
        duplicate_disabled.unlink()

        regular_input = local_inputs / "20-copied.conf"
        if regular_input.is_symlink() or regular_input.is_file():
            regular_input.unlink()
        regular_input.mkdir()
        rejected_directory = run([str(sync_inputs), "--strategy", "copy", "main"], cwd=temporary, env=env_one, check=False)
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
        assert list(bypass_plan["spec"]["contexts"]) == ["canonical"]
        assert "config-install.sh" in {item["name"] for item in bypass_plan["bins"]}


if __name__ == "__main__":
    test_config_context_toolkit()
    print("ok: config context donor toolkit")
