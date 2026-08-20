#!/usr/bin/env python3

"""SYSTEMD_INSTALL normalization and enum validation.

CLI extra-vars are strings, so the documented `true` / `false` spellings must
normalize to booleans before SYSTEMD_INSTALL_VALID applies its enum. Genuine
misspellings should still fail loudly rather than silently disable every gate.
"""

import subprocess
import tempfile
from pathlib import Path


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


def main() -> None:
    check("false", "RESULT=false, false, false")
    check("true", "RESULT=true, true, true")
    check("none", "RESULT=none, false, false")
    check("separate", "RESULT=separate, true, true")

    typo = render("seperate")
    if typo.returncode == 0 or "not one of enum" not in (typo.stdout + typo.stderr):
        raise AssertionError(
            "SYSTEMD_INSTALL='seperate' should fail enum validation\n"
            f"stdout:\n{typo.stdout}\nstderr:\n{typo.stderr}"
        )
    print("ok: SYSTEMD_INSTALL=seperate fails enum validation")


if __name__ == "__main__":
    main()
