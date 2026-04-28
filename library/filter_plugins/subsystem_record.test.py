#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from subsystem_record import build_install_bins, subsystem_record

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


# --- build_install_bins ---


def test_build_install_bins_normal():
    print("\nbuild_install_bins: normal stem")
    result = build_install_bins("sysctl")
    expected = {
        "build_bins": [
            {"name": "build-sysctl.sh", "src": "../kernel/build-sysctl.sh", "basedir": False}
        ],
        "install_bins": [
            {"name": "install-sysctl.sh", "src": "../kernel/install-sysctl.sh", "basedir": False}
        ],
    }
    check("normal stem produces correct entries", result, expected)


def test_build_install_bins_empty():
    print("\nbuild_install_bins: empty stem")
    result = build_install_bins("")
    check("empty stem returns empty lists", result, {"build_bins": [], "install_bins": []})


def test_build_install_bins_basedir():
    print("\nbuild_install_bins: basedir=True")
    result = build_install_bins("kernel", basedir=True)
    check(
        "basedir flag forwarded",
        result["build_bins"][0]["basedir"],
        True,
    )
    check(
        "install basedir forwarded",
        result["install_bins"][0]["basedir"],
        True,
    )


def test_build_install_bins_custom_src_root():
    print("\nbuild_install_bins: custom src_root")
    result = build_install_bins("foo", src_root="/custom")
    check(
        "build src uses custom root",
        result["build_bins"][0]["src"],
        "/custom/build-foo.sh",
    )
    check(
        "install src uses custom root",
        result["install_bins"][0]["src"],
        "/custom/install-foo.sh",
    )


# --- subsystem_record ---


def test_subsystem_record_defaults():
    print("\nsubsystem_record: all defaults from empty context")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test")
    expected = {
        "status": "requested",
        "requested": False,
        "bypassed": False,
        "valid": True,
        "active": False,
        "reasons": [],
        "subsystem": "test",
    }
    check("defaults from empty context", result, expected)


def test_subsystem_record_active():
    print("\nsubsystem_record: active state")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=True, bypassed=False, valid=True)
    expected = {
        "status": "active",
        "requested": True,
        "bypassed": False,
        "valid": True,
        "active": True,
        "reasons": [],
        "subsystem": "test",
    }
    check("requested+valid→active", result, expected)


def test_subsystem_record_spec_included():
    print("\nsubsystem_record: spec included when valid+requested")
    ctx = {"vars": {}}
    spec = {"key": "val"}
    result = subsystem_record(ctx, "test", requested=True, valid=True, spec=spec)
    check("spec present", "spec" in result, True)
    check("spec value", result["spec"], spec)


def test_subsystem_record_spec_excluded_when_invalid():
    print("\nsubsystem_record: spec excluded when not valid")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=True, valid=False, spec={"key": "val"})
    check("spec absent when invalid", "spec" in result, False)


def test_subsystem_record_spec_excluded_when_not_requested():
    print("\nsubsystem_record: spec excluded when not requested")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=False, valid=True, spec={"key": "val"})
    check("spec absent when not requested", "spec" in result, False)


def test_subsystem_record_spec_excluded_when_empty():
    print("\nsubsystem_record: spec excluded when empty payload")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=True, valid=True, spec={})
    check("spec absent when empty dict", "spec" in result, False)
    result2 = subsystem_record(ctx, "test", requested=True, valid=True, spec=None)
    check("spec absent when None", "spec" in result2, False)


def test_subsystem_record_contrib_included():
    print("\nsubsystem_record: contrib included when active")
    ctx = {"vars": {}}
    contrib = {"data": [1, 2]}
    result = subsystem_record(ctx, "test", requested=True, valid=True, contrib=contrib)
    check("contrib present", "contrib" in result, True)
    check("contrib value", result["contrib"], contrib)


def test_subsystem_record_contrib_excluded_when_inactive():
    print("\nsubsystem_record: contrib excluded when not active")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=False, valid=True, contrib={"a": 1})
    check("contrib absent when inactive", "contrib" in result, False)


def test_subsystem_record_contrib_excluded_when_empty():
    print("\nsubsystem_record: contrib excluded when empty payload")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=True, valid=True, contrib={})
    check("contrib absent when empty dict", "contrib" in result, False)


def test_subsystem_record_invalid_status():
    print("\nsubsystem_record: invalid state → status invalid")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=True, valid=False, bypassed=False)
    check("status is invalid", result["status"], "invalid")
    check("active is False", result["active"], False)


def test_subsystem_record_bypassed_status():
    print("\nsubsystem_record: bypassed state → status bypassed")
    ctx = {"vars": {}}
    result = subsystem_record(ctx, "test", requested=True, valid=True, bypassed=True)
    check("status is bypassed", result["status"], "bypassed")
    check("active is False", result["active"], False)


def test_subsystem_record_context_requested():
    print("\nsubsystem_record: requested from context vars")
    ctx = {"vars": {"requested": True}}
    result = subsystem_record(ctx, "test")
    check("requested from context", result["requested"], True)
    check("status is active", result["status"], "active")


def test_subsystem_record_context_errors():
    print("\nsubsystem_record: errors from context vars")
    ctx = {"vars": {"errors": ["something broke"]}}
    result = subsystem_record(ctx, "test", requested=True)
    check("errors from context", result["reasons"], ["something broke"])
    check("valid is False", result["valid"], False)
    check("status is invalid", result["status"], "invalid")


if __name__ == "__main__":
    test_build_install_bins_normal()
    test_build_install_bins_empty()
    test_build_install_bins_basedir()
    test_build_install_bins_custom_src_root()

    test_subsystem_record_defaults()
    test_subsystem_record_active()
    test_subsystem_record_spec_included()
    test_subsystem_record_spec_excluded_when_invalid()
    test_subsystem_record_spec_excluded_when_not_requested()
    test_subsystem_record_spec_excluded_when_empty()
    test_subsystem_record_contrib_included()
    test_subsystem_record_contrib_excluded_when_inactive()
    test_subsystem_record_contrib_excluded_when_empty()
    test_subsystem_record_invalid_status()
    test_subsystem_record_bypassed_status()
    test_subsystem_record_context_requested()
    test_subsystem_record_context_errors()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
