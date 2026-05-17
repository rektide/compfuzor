#!/usr/bin/env python3

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'lookup_plugins'))

from subsys import (
    _resolve_bypass,
    _resolve_record,
    _compute_state,
)

passed = 0
failed = 0


def check(name, actual, expected):
    global passed, failed
    if actual == expected:
        passed += 1
        print("  PASS: {}".format(name))
    else:
        failed += 1
        print("  FAIL: {}".format(name))
        print("    actual:   {}".format(actual))
        print("    expected: {}".format(expected))


def _build_minimal_envelope(subsystems, subsystem_id, variables=None, domain=None, extra_bypass=None, name=None, templar=None):
    variables = variables or {}
    variables_with_subsystem = dict(variables)
    variables_with_subsystem["SUBSYSTEM"] = subsystems
    record = _resolve_record(variables_with_subsystem, subsystem_id)
    st = _compute_state(record, variables_with_subsystem, subsystem_id, domain=domain, extra_bypass=extra_bypass, templar=templar)
    return {
        "id": subsystem_id,
        "name": name if isinstance(name, str) and name.strip() else subsystem_id,
        "record": record,
        **st,
    }


def test_active_record():
    print("\nactive record:")
    env = _build_minimal_envelope(
        {"get_urls": {"requested": True, "valid": True, "contrib": {"BINS": []}}},
        "get_urls",
    )
    check("status active", env["status"], "active")
    check("active true", env["active"], True)
    check("name defaults to id", env["name"], "get_urls")


def test_missing_record():
    print("\nmissing record:")
    env = _build_minimal_envelope({}, "kernel", name="kernel-main")
    check("record empty", env["record"], {})
    check("status absent", env["status"], "absent")
    check("alias name kept", env["name"], "kernel-main")


def test_status_from_booleans():
    print("\nstatus from booleans:")
    env = _build_minimal_envelope({"go": {"requested": True, "bypassed": True}}, "go")
    check("status bypassed", env["status"], "bypassed")
    check("bypassed true", env["bypassed"], True)


def test_resolve_bypass_subsystem_var():
    print("\nresolve_bypass: subsystem var")
    check("GO_BYPASS true", _resolve_bypass({"GO_BYPASS": True}, "go"), True)
    check("GO_BYPASS false", _resolve_bypass({"GO_BYPASS": False}, "go"), False)
    check("GO_BYPASS absent", _resolve_bypass({}, "go"), False)


def test_resolve_bypass_domain_var():
    print("\nresolve_bypass: domain var")
    check("KERNEL_BYPASS true", _resolve_bypass({"KERNEL_BYPASS": True}, "kernel_sysctl", domain="kernel"), True)
    check("KERNEL_BYPASS false", _resolve_bypass({"KERNEL_BYPASS": False}, "kernel_sysctl", domain="kernel"), False)
    check("no domain", _resolve_bypass({}, "kernel_sysctl"), False)


def test_resolve_bypass_extra():
    print("\nresolve_bypass: extra bypass vars")
    check("extra string true", _resolve_bypass({"BINS_RUN_BYPASS": True}, "go", extra_bypass="BINS_RUN_BYPASS"), True)
    check("extra string false", _resolve_bypass({"BINS_RUN_BYPASS": False}, "go", extra_bypass="BINS_RUN_BYPASS"), False)
    check("extra list true", _resolve_bypass({"MY_VAR": True}, "go", extra_bypass=["MY_VAR", "OTHER"]), True)
    check("extra absent", _resolve_bypass({}, "go", extra_bypass="MISSING_VAR"), False)


def test_resolve_bypass_combined():
    print("\nresolve_bypass: combined sources")
    check("subsystem + domain", _resolve_bypass({"KERNEL_BYPASS": True}, "kernel_sysctl", domain="kernel"), True)
    check("subsystem overrides domain false", _resolve_bypass({"KERNEL_SYSCTL_BYPASS": True, "KERNEL_BYPASS": False}, "kernel_sysctl", domain="kernel"), True)


def test_envelope_with_variables_bypass():
    print("\nenvelope: variables-based bypass")
    env = _build_minimal_envelope(
        {"go": {"requested": True, "bypassed": False, "valid": True}},
        "go",
        variables={"GO_BYPASS": True},
    )
    check("bypassed from var", env["bypassed"], True)
    check("active false when bypassed", env["active"], False)
    check("status bypassed", env["status"], "bypassed")


def test_envelope_with_domain_bypass():
    print("\nenvelope: domain bypass")
    env = _build_minimal_envelope(
        {"kernel_sysctl": {"requested": True, "bypassed": False, "valid": True}},
        "kernel_sysctl",
        variables={"KERNEL_BYPASS": True},
        domain="kernel",
    )
    check("domain bypass", env["bypassed"], True)
    check("status bypassed", env["status"], "bypassed")


def test_envelope_without_variables():
    print("\nenvelope: no variables (backward compat)")
    env = _build_minimal_envelope(
        {"go": {"requested": True, "bypassed": False, "valid": True}},
        "go",
    )
    check("not bypassed", env["bypassed"], False)
    check("active", env["active"], True)


def test_compute_state_active():
    print("\n_compute_state: active from record booleans")
    record = {"requested": True, "valid": True}
    variables = {"SUBSYSTEM": {"go": record}}
    st = _compute_state(record, variables, "go")
    check("active", st["active"], True)
    check("requested", st["requested"], True)
    check("valid", st["valid"], True)


def test_compute_state_bypassed_from_env_var():
    print("\n_compute_state: bypassed from env var")
    record = {"requested": True, "valid": True}
    variables = {"SUBSYSTEM": {"go": record}, "GO_BYPASS": True}
    st = _compute_state(record, variables, "go")
    check("bypassed", st["bypassed"], True)
    check("active", st["active"], False)


def test_compute_state_valid_defaults():
    print("\n_compute_state: valid defaults")
    check("valid when absent", _compute_state({}, {}, "x")["valid"], True)
    check("valid when true", _compute_state({"valid": True}, {}, "x")["valid"], True)
    check("invalid when false", _compute_state({"valid": False}, {}, "x")["valid"], False)


def test_compute_state_requested_from_variable():
    print("\n_compute_state: requested from variable")
    st = _compute_state({}, {"RUST": True}, "rust")
    check("requested from RUST var", st["requested"], True)
    check("active", st["active"], True)


if __name__ == "__main__":
    test_active_record()
    test_missing_record()
    test_status_from_booleans()
    test_resolve_bypass_subsystem_var()
    test_resolve_bypass_domain_var()
    test_resolve_bypass_extra()
    test_resolve_bypass_combined()
    test_envelope_with_variables_bypass()
    test_envelope_with_domain_bypass()
    test_envelope_without_variables()
    test_compute_state_active()
    test_compute_state_bypassed_from_env_var()
    test_compute_state_valid_defaults()
    test_compute_state_requested_from_variable()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
