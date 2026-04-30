#!/usr/bin/env python3

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'lookup_plugins'))

from subsys import _build_envelope, _resolve_bypass

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


def test_active_record():
    print("\nactive record:")
    env = _build_envelope(
        {"get_urls": {"active": True, "requested": True, "valid": True, "contrib": {"BINS": []}}},
        "get_urls",
    )
    check("state active", env["state"], "active")
    check("active true", env["active"], True)
    check("name defaults to id", env["name"], "get_urls")


def test_missing_record():
    print("\nmissing record:")
    env = _build_envelope({}, "kernel", name="kernel-main")
    check("found false", env["found"], False)
    check("state absent", env["state"], "absent")
    check("alias name kept", env["name"], "kernel-main")


def test_state_from_booleans():
    print("\nstate from booleans:")
    env = _build_envelope({"go": {"requested": True, "bypassed": True}}, "go")
    check("state bypassed", env["state"], "bypassed")
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
    env = _build_envelope(
        {"go": {"requested": True, "bypassed": False, "valid": True}},
        "go",
        variables={"GO_BYPASS": True},
    )
    check("bypassed from var", env["bypassed"], True)
    check("active false when bypassed", env["active"], False)
    check("state bypassed", env["state"], "bypassed")


def test_envelope_with_domain_bypass():
    print("\nenvelope: domain bypass")
    env = _build_envelope(
        {"kernel_sysctl": {"requested": True, "bypassed": False, "valid": True}},
        "kernel_sysctl",
        variables={"KERNEL_BYPASS": True},
        domain="kernel",
    )
    check("domain bypass", env["bypassed"], True)
    check("state bypassed", env["state"], "bypassed")


def test_envelope_without_variables():
    print("\nenvelope: no variables (backward compat)")
    env = _build_envelope(
        {"go": {"requested": True, "bypassed": False, "valid": True}},
        "go",
    )
    check("not bypassed", env["bypassed"], False)
    check("active", env["active"], True)


if __name__ == "__main__":
    test_active_record()
    test_missing_record()
    test_state_from_booleans()
    test_resolve_bypass_subsystem_var()
    test_resolve_bypass_domain_var()
    test_resolve_bypass_extra()
    test_resolve_bypass_combined()
    test_envelope_with_variables_bypass()
    test_envelope_with_domain_bypass()
    test_envelope_without_variables()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
