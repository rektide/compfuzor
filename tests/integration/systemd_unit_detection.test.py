#!/usr/bin/env python3
"""Top-level SYSTEMD unit-type detection drives rendering for every type."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]

PLAYBOOK = """---
- hosts: all
  gather_facts: false
  vars_files:
    - @ROOT@/vars/systemd.yaml
  vars:
    NAME: tl
@VARS@
  tasks:
    - import_tasks: @ROOT@/tasks/compfuzor/vars_systemd_unit.tasks
    - copy:
        dest: "@OUTPUT@"
        content: "{{ {'types': SYSTEMD_UNITTYPES, 'has_units': _systemd_has_units, 'files': ETC_FILES|default([])} | to_json }}"
"""

TIMER_VARS = """    SYSTEMD_UNITS:
      Description: top-level timer probe
    SYSTEMD_TIMERS:
      OnCalendar: daily
      Persistent: true
"""

DNSSD_VARS = """    SYSTEMD_DNSSDS:
      Port: "49373"
"""

MIXED_VARS = """    SYSTEMD_SERVICES:
      ExecStart: /bin/true
    SYSTEMD_TIMERS:
      OnCalendar: daily
"""


def render(extra_vars: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="compfuzor-systemd-detect-") as temporary:
        output = Path(temporary) / "out.json"
        playbook = ROOT / ".test-agent-systemd-detection.pb"
        playbook.write_text(
            PLAYBOOK.replace("@ROOT@", str(ROOT))
            .replace("@VARS@", extra_vars)
            .replace("@OUTPUT@", str(output)),
            encoding="utf-8",
        )
        try:
            result = subprocess.run(
                ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
        finally:
            playbook.unlink(missing_ok=True)
        if result.returncode != 0:
            raise AssertionError(f"detection render failed:\n{result.stdout}{result.stderr}")
        return json.loads(output.read_text(encoding="utf-8"))


def test_top_level_timer_is_detected_and_rendered():
    rendered = render(TIMER_VARS)
    if rendered["types"] != ["timer"]:
        raise AssertionError(f"expected timer detection, got {rendered['types']!r}")
    if rendered["has_units"] is not True:
        raise AssertionError(f"expected has_units true: {rendered}")
    files = {entry["name"]: entry["content"] for entry in rendered["files"]}
    if set(files) != {"tl.timer"}:
        raise AssertionError(f"unexpected rendered units: {sorted(files)}")
    content = files["tl.timer"]
    for fragment in ("[Timer]", "OnCalendar=daily", "Persistent=True"):
        if fragment not in content:
            raise AssertionError(f"timer unit missing {fragment!r}:\n{content}")


def test_top_level_dnssd_no_longer_masquerades_as_timer():
    rendered = render(DNSSD_VARS)
    if rendered["types"] != ["dnssd"]:
        raise AssertionError(f"expected dnssd detection, got {rendered['types']!r}")
    names = {entry["name"] for entry in rendered["files"]}
    if names != {"tl.dnssd"}:
        raise AssertionError(f"unexpected rendered units: {sorted(names)}")


def test_service_and_timer_detect_together_in_config_order():
    rendered = render(MIXED_VARS)
    if rendered["types"] != ["service", "timer"]:
        raise AssertionError(f"expected ['service', 'timer'], got {rendered['types']!r}")
    names = {entry["name"] for entry in rendered["files"]}
    if not {"tl.service", "tl.timer"} <= names:
        raise AssertionError(f"missing units: {sorted(names)}")


def test_no_units_yields_empty_detection():
    rendered = render("")
    if rendered["types"] != [] or rendered["has_units"] is not False:
        raise AssertionError(f"expected empty detection: {rendered}")
    if rendered["files"] != []:
        raise AssertionError(f"unexpected units: {rendered['files']}")


if __name__ == "__main__":
    test_top_level_timer_is_detected_and_rendered()
    test_top_level_dnssd_no_longer_masquerades_as_timer()
    test_service_and_timer_detect_together_in_config_order()
    test_no_units_yields_empty_detection()
    print("ok: top-level systemd unit-type detection")
