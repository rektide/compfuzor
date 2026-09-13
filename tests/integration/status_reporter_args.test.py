#!/usr/bin/env python3
"""Exercise structured aggregate status arguments and legacy exit-2 behavior."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_status_reporter_args() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-status-args-") as tmp:
        root = Path(tmp)
        payload = root / "deployment"
        playbook = root / "render.pb"
        log = root / "args.log"
        (root / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook.write_text(
            f"""---
- hosts: all
  gather_facts: false
  vars_files: [{str(ROOT / 'vars' / 'common.yaml')!r}]
  vars:
    TYPE: status-args-test
    NAME: status-args-test
    DIR: {str(payload)!r}
    BINS_DIR: {str(payload / 'bin')!r}
    STATUSES:
      - legacy.sh
      - name: structured.sh
        args: [--activation-only, fixed value]
        exit2: error
  tasks:
    - file: {{path: "{{{{ BINS_DIR }}}}", state: directory}}
    - copy:
        dest: "{{{{ BINS_DIR }}}}/legacy.sh"
        mode: '0770'
        content: |
          #!/bin/bash
          printf 'legacy:%s\\n' "$*" >> {str(log)!r}
          exit 2
    - copy:
        dest: "{{{{ BINS_DIR }}}}/structured.sh"
        mode: '0770'
        content: |
          #!/bin/bash
          printf 'structured:' >> {str(log)!r}
          printf '<%s>' "$@" >> {str(log)!r}
          printf '\\n' >> {str(log)!r}
          exit 2
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
""",
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        rendered = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        assert rendered.returncode == 0, (rendered.stdout, rendered.stderr)
        result = subprocess.run(
            [str(payload / "bin" / "status.sh"), "caller value"],
            cwd=root,
            env=env | {"DIR": str(payload)},
            check=False,
            text=True,
            capture_output=True,
        )
        assert result.returncode == 1, (
            result.returncode, result.stdout, result.stderr,
            log.read_text(encoding="utf-8") if log.exists() else "missing log",
            (payload / "bin" / "status.sh").read_text(encoding="utf-8"),
        )
        assert log.read_text(encoding="utf-8").splitlines() == [
            "legacy:caller value",
            "structured:<--activation-only><fixed value><caller value>",
        ]


if __name__ == "__main__":
    test_status_reporter_args()
    print("ok: structured aggregate status arguments")
