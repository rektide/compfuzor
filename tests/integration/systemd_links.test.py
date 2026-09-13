#!/usr/bin/env python3
"""Systemd publication uses LINKS representations without later-plan undo."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def generate(payload: Path) -> None:
    output = payload.parent / "rendered.json"
    playbook = ROOT / ".test-agent-systemd-links.pb"
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {ROOT / 'vars/common.yaml'}
    - {ROOT / 'vars/systemd.yaml'}
  vars:
    TYPE: systemd-links-test
    NAME: probe
    DIR: {str(payload)!r}
    BINS_DIR: {str(payload / 'bin')!r}
    ETC: {str(payload / 'etc')!r}
    DIRSET: [etc]
    FILES: []
    BINS: []
    LINKS: []
    STATUSES: []
    ENV: {{}}
    ENV_LIST: []
    SYSTEMD_SERVICE: probe
    SYSTEMD_SERVICES:
      ExecStart: /bin/true
    SYSTEMD_ENABLE: false
    SYSTEMD_INSTALL: system
  tasks:
    - import_tasks: {ROOT / 'tasks/compfuzor/vars_systemd_unit.tasks'}
    - import_tasks: {ROOT / 'tasks/compfuzor/compile_artifacts.tasks'}
    - import_tasks: {ROOT / 'tasks/compfuzor/gen_links.tasks'}
    - import_tasks: {ROOT / 'tasks/compfuzor/gen_bins.tasks'}
    - file:
        path: {str(payload / 'etc')!r}
        state: directory
    - file:
        path: {str(payload / 'bin/links')!r}
        state: directory
    - copy:
        dest: "{payload}/etc/{{{{ item.name }}}}"
        content: "{{{{ item.content }}}}"
      loop: "{{{{ ETC_FILES }}}}"
    - import_tasks: {ROOT / 'tasks/compfuzor/link_plan.tasks'}
    - import_tasks: {ROOT / 'tasks/compfuzor/bins.tasks'}
    - copy:
        dest: {str(output)!r}
        content: >-
          {{{{ {{'plan': _LINK_PLAN, 'bins': BINS}} | to_json }}}}
""",
        encoding="utf-8",
    )
    try:
        result = subprocess.run(
            [
                "ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                "-e", json.dumps({
                    "TYPE": "systemd-links-test",
                    "NAME": "probe",
                    "DIR": str(payload),
                    "BINS_DIR": str(payload / "bin"),
                    "ETC": str(payload / "etc"),
                    "SYSTEMD_ENABLE": False,
                    "SYSTEMD_INSTALL": "system",
                }),
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
    finally:
        playbook.unlink(missing_ok=True)
    if result.returncode != 0:
        raise AssertionError(f"systemd/LINKS render failed:\n{result.stdout}{result.stderr}")

    rendered = json.loads(output.read_text(encoding="utf-8"))
    assert rendered["plan"]["version"] == 2
    record = rendered["plan"]["links"][0]
    assert record["dest"] == "/etc/systemd/system/probe.service"
    assert record["strategies"] == {"available": ["link", "copy"], "default": "link"}
    assert record["compose"] is False
    by_name = {item["name"]: item for item in rendered["bins"]}
    assert by_name["install.sh"]["run_all"] == ["install-systemd.sh", "install-links.sh"]
    assert by_name["install-link-records.sh"]["content"] == 'exec "$DIR/bin/links.ts" apply --composed --scope system'


def retarget_fixture(payload: Path, unit_dir: Path) -> tuple[str, Path, Path]:
    manifest = payload / "links.json"
    plan = json.loads(manifest.read_text(encoding="utf-8"))
    record = plan["links"][0]
    old_dest = record["dest"]
    old_id = record["id"]
    destination = unit_dir / "probe.service"
    new_id = f"system:{destination}"
    record["dest"] = str(destination)
    record["id"] = new_id
    manifest.write_text(json.dumps(plan), encoding="utf-8")

    leaf = payload / "bin/install-service.sh"
    text = leaf.read_text(encoding="utf-8")
    text = text.replace(f'UNIT_DIR="{Path(old_dest).parent}"', f'UNIT_DIR="{unit_dir}"')
    text = text.replace(f"UNIT_LINK_ID='{old_id}'", f"UNIT_LINK_ID='{new_id}'")
    leaf.write_text(text, encoding="utf-8")
    return new_id, payload / "etc/probe.service", destination


def fake_commands(root: Path) -> tuple[dict[str, str], Path, Path]:
    shim = root / "shim"
    shim.mkdir()
    sudo_log = root / "sudo.log"
    systemctl_log = root / "systemctl.log"
    (shim / "sudo").write_text(
        "#!/bin/sh\n"
        f'printf \'%s\\n\' "$*" >> {sudo_log}\n'
        'exec "$@"\n',
        encoding="utf-8",
    )
    (shim / "systemctl").write_text(
        "#!/bin/sh\n"
        f'printf \'%s\\n\' "$*" >> {systemctl_log}\n',
        encoding="utf-8",
    )
    (shim / "sudo").chmod(0o755)
    (shim / "systemctl").chmod(0o755)
    env = {
        **os.environ,
        "PATH": f"{shim}:{os.environ['PATH']}",
        "ENV_BYPASS": "1",
        "COMPFUZOR_LINKS_SUDO": "auto",
    }
    for variable in (
        "SYSTEMD_COPY",
        "SYSTEMD_INSTALL_COPY",
        "COMPFUZOR_SYSTEMD_LINK_BYPASS",
        "SYSTEMD_BYPASS_LINK",
    ):
        env.pop(variable, None)
    return env, sudo_log, systemctl_log


def run(command: Path, *args: str, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(command), *args], env=env, text=True, capture_output=True, check=False)
    if check and result.returncode != 0:
        raise AssertionError(f"{command.name} failed:\n{result.stdout}{result.stderr}")
    return result


def status(payload: Path, env: dict[str, str]) -> dict:
    result = run(payload / "bin/links.ts", "status", "--json-array", env=env)
    rows = json.loads(result.stdout)
    assert len(rows) == 1, (result.stdout, result.stderr)
    return rows[0]


def test_rendered_aggregate_preserves_or_switches_declared_representation() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-systemd-links-") as tmp:
        root = Path(tmp)
        payload = root / "payload"
        payload.mkdir()
        generate(payload)
        link_id, source, destination = retarget_fixture(payload, root / "units")
        env, sudo_log, systemctl_log = fake_commands(root)
        env["DIR"] = str(payload)
        aggregate = payload / "bin/install.sh"

        run(aggregate, "--skip-enable", env=env)
        assert destination.is_symlink() and destination.resolve() == source
        assert status(payload, env)["representation"] == "link"

        run(aggregate, "--copy", "--skip-enable", env=env)
        assert destination.is_file() and not destination.is_symlink()
        assert destination.read_bytes() == source.read_bytes()
        assert status(payload, env)["representation"] == "copy"

        # No selection preserves the healthy nondefault copy rather than
        # returning to the record's link default.
        run(aggregate, "--skip-enable", env=env)
        assert destination.is_file() and not destination.is_symlink()

        # Explicit strategy outranks the legacy copy environment.
        run(aggregate, "--link", "--skip-enable", env={**env, "SYSTEMD_COPY": "1"})
        assert destination.is_symlink() and destination.resolve() == source

        run(aggregate, "--skip-enable", env={**env, "SYSTEMD_INSTALL_COPY": "1"})
        assert destination.is_file() and not destination.is_symlink()

        # The systemd publication bypass remains authoritative when the later
        # generic records lane runs: compose:false omits this record.
        destination.unlink()
        run(aggregate, "--skip-enable", env={**env, "COMPFUZOR_SYSTEMD_LINK_BYPASS": "1"})
        assert not destination.exists() and not destination.is_symlink()
        missing = run(payload / "bin/links.ts", "status", "--json-array", env=env, check=False)
        assert missing.returncode == 1 and json.loads(missing.stdout)[0]["status"] == "MISSING"

        run(payload / "bin/install-link-records.sh", env=env)
        assert not destination.exists() and not destination.is_symlink()
        run(payload / "bin/links.ts", "apply", "--id", link_id, env=env)
        assert destination.is_symlink()

        assert "daemon-reload" in systemctl_log.read_text(encoding="utf-8")
        # Only manager operations need the generated sudo binding in this
        # writable fixture; LINKS auto-routing remains per destination.
        assert "systemctl daemon-reload" in sudo_log.read_text(encoding="utf-8")


if __name__ == "__main__":
    test_rendered_aggregate_preserves_or_switches_declared_representation()
    print("ok: systemd unit representations survive complete LINKS composition")
