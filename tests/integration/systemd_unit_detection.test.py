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


def render(extra_vars: str, overrides: dict | None = None) -> dict:
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
                ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                 "-e", json.dumps(overrides or {})],
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


def test_defaults_and_shared_sections_do_not_declare_units():
    rendered = render("""    SYSTEMD_UNITS: {}
    SYSTEMD_INSTALLS: {}
    SYSTEMD_SERVICES_DEFAULT:
      Restart: always
""")
    assert rendered["types"] == []
    assert rendered["has_units"] is False
    assert rendered["files"] == []


def test_service_defaults_require_sections_and_do_not_create_install_alias():
    rendered = render("""    INSTANCE: main
    SYSTEMD_SERVICE: probe-main
    SYSTEMD_SERVICES:
      ExecStart: /bin/true
""")
    content = rendered["files"][0]["content"]
    for directive in ("[Service]", "Type=simple", "Restart=on-failure", "RestartSec=5"):
        assert directive in content, content
    for absent in ("[Unit]", "[Install]", "WantedBy=", "Alias="):
        assert absent not in content, content


def test_empty_sections_opt_in_and_explicit_values_override_defaults():
    rendered = render("""    SYSTEMD_UNITS: {}
    SYSTEMD_SERVICES:
      ExecStart: /bin/true
      Type: exec
      Restart: "no"
      RestartSec: false
    SYSTEMD_INSTALLS: {}
""", {"SYSTEMD_SCOPE": "user", "SYSTEMD_INSTALL": "user"})
    content = rendered["files"][0]["content"]
    for directive in ("Description=tl", "DefaultDependencies=True", "Type=exec",
                      "Restart=no", "[Install]", "WantedBy=default.target"):
        assert directive in content, content
    assert "RestartSec=" not in content, content


def test_root_sections_gate_defaults_and_suppress_global_inheritance():
    rendered = render("""    SYSTEMD_UNITS: {}
    SYSTEMD_INSTALLS: {}
    SYSTEMD_ROOTS: [inherited, suppressed, namedOnly]
    inherited:
      SYSTEMD_SERVICE: inherited
      SYSTEMD_SERVICES:
        ExecStart: /bin/true
    suppressed:
      SYSTEMD_SERVICE: suppressed
      SYSTEMD_ALIAS: suppressed-alias
      SYSTEMD_UNITS: null
      SYSTEMD_SERVICES:
        ExecStart: /bin/true
      SYSTEMD_INSTALLS: false
    namedOnly:
      SYSTEMD_SERVICE: named-only
""")
    files = {entry["name"]: entry["content"] for entry in rendered["files"]}
    assert set(files) == {"inherited.service", "suppressed.service", "named-only.service"}
    for directive in ("Description=tl", "Restart=on-failure", "WantedBy=multi-user.target"):
        assert directive in files["inherited.service"]
    for absent in ("[Unit]", "[Install]", "Alias="):
        assert absent not in files["suppressed.service"]
    assert "Restart=on-failure" in files["suppressed.service"]
    assert "[Service]" not in files["named-only.service"]


def test_root_local_sections_receive_defaults_without_inventing_other_sections():
    rendered = render("""    SYSTEMD_SERVICE: top
    SYSTEMD_VARS_ROOT: topData
    topData:
      SYSTEMD_SERVICES:
        ExecStart: /bin/true
    SYSTEMD_ROOTS: [localData]
    localData:
      SYSTEMD_SERVICE: local
      SYSTEMD_ALIAS: local-alias
      SYSTEMD_SERVICES:
        ExecStart: /bin/true
""")
    files = {entry["name"]: entry["content"] for entry in rendered["files"]}
    assert set(files) == {"top.service", "local.service"}
    for content in files.values():
        assert "Restart=on-failure" in content, content
        assert "ExecStart=/bin/true" in content, content
        for absent in ("[Unit]", "[Install]", "Alias="):
            assert absent not in content, content


if __name__ == "__main__":
    test_top_level_timer_is_detected_and_rendered()
    test_top_level_dnssd_no_longer_masquerades_as_timer()
    test_service_and_timer_detect_together_in_config_order()
    test_no_units_yields_empty_detection()
    test_defaults_and_shared_sections_do_not_declare_units()
    test_service_defaults_require_sections_and_do_not_create_install_alias()
    test_empty_sections_opt_in_and_explicit_values_override_defaults()
    test_root_sections_gate_defaults_and_suppress_global_inheritance()
    test_root_local_sections_receive_defaults_without_inventing_other_sections()
    print("ok: top-level systemd unit-type detection")
