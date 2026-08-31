#!/usr/bin/env python3

"""SYSTEMD_INSTALL normalization and enum validation.

CLI extra-vars are strings, so the documented `true` / `false` spellings must
normalize to booleans before SYSTEMD_INSTALL_VALID applies its enum. Genuine
misspellings should still fail loudly rather than silently disable every gate.
"""

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def render(value: str) -> subprocess.CompletedProcess[str]:
    playbook = f"""
- hosts: all
  gather_facts: false
  vars_files:
    - {ROOT / 'vars/systemd.yaml'}
  tasks:
    - debug:
        msg: >-
          RESULT={{{{ SYSTEMD_INSTALL_VALID|string|lower }}}},
          {{{{ SYSTEMD_SYSTEM_SERVICE_INSTALL|string|lower }}}},
          {{{{ SYSTEMD_USER_SERVICE_INSTALL|string|lower }}}}
"""
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / "probe.pb"
        path.write_text(playbook, encoding="utf-8")
        return subprocess.run(
            [
                "ansible-playbook",
                "-i",
                "localhost,",
                "-c",
                "local",
                str(path),
                "-e",
                f"SYSTEMD_INSTALL={value}",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )


def check(value: str, expected: str) -> None:
    result = render(value)
    if result.returncode != 0 or expected not in result.stdout:
        raise AssertionError(
            f"SYSTEMD_INSTALL={value!r}: expected {expected!r}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    print(f"ok: SYSTEMD_INSTALL={value} -> {expected}")


def check_user_timer_installer() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-systemd-timer-") as temporary:
        output = Path(temporary) / "bins.json"
        playbook_path = ROOT / ".test-agent-systemd-user-timer.pb"
        playbook_path.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files:
    - {ROOT / 'vars/systemd.yaml'}
  vars:
    NAME: probe
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_ROOTS: [probeTimer]
    probeTimer:
      SYSTEMD_TIMER: probe
      SYSTEMD_TIMERS: {{OnCalendar: daily, Persistent: true}}
  tasks:
    - import_tasks: {ROOT / 'tasks/compfuzor/vars_systemd_unit.tasks'}
    - copy:
        dest: {str(output)!r}
        content: >-
          {{{{ {{'bins': BINS,
                 'install': SYSTEMD_INSTALL_VALID}} | to_json }}}}
""",
            encoding="utf-8",
        )
        try:
            result = subprocess.run(
                [
                    "ansible-playbook",
                    "-i",
                    "localhost,",
                    "-c",
                    "local",
                    str(playbook_path),
                    "-e",
                    "SYSTEMD_INSTALL=user",
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )
        finally:
            playbook_path.unlink(missing_ok=True)

        if result.returncode != 0:
            raise AssertionError(f"user timer render failed:\n{result.stdout}{result.stderr}")
        rendered = json.loads(output.read_text())
        if rendered["install"] != "user":
            raise AssertionError(f"test harness did not select user install: {rendered}")
        bins = {entry["name"]: entry for entry in rendered["bins"]}
        name = "install-timer-user.sh"
        if name not in bins:
            raise AssertionError(
                f"user timer installer missing; got {sorted(bins)}; gates={rendered}"
            )
        generated = bins[name]["generated"]
        expected_fragments = (
            'UNIT_DIR="${HOME}/.config/systemd/user"',
            'SYSTEMCTL="systemctl --user"',
        )
        for fragment in expected_fragments:
            if fragment not in generated:
                raise AssertionError(
                    f"user timer installer missing {fragment!r}:\n{generated}"
                )
        print("ok: SYSTEMD_INSTALL=user routes timer installer to user scope")


def main() -> None:
    check("false", "RESULT=false, false, false")
    check("true", "RESULT=true, true, true")
    check("none", "RESULT=none, false, false")
    check("separate", "RESULT=separate, true, true")
    check("user", "RESULT=user, false, true")
    check_user_timer_installer()

    typo = render("seperate")
    if typo.returncode == 0 or "not one of enum" not in (typo.stdout + typo.stderr):
        raise AssertionError(
            "SYSTEMD_INSTALL='seperate' should fail enum validation\n"
            f"stdout:\n{typo.stdout}\nstderr:\n{typo.stderr}"
        )
    print("ok: SYSTEMD_INSTALL=seperate fails enum validation")


if __name__ == "__main__":
    main()
