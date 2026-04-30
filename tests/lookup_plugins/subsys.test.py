#!/usr/bin/env python3

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'lookup_plugins'))

from subsys import _build_envelope

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


if __name__ == "__main__":
    test_active_record()
    test_missing_record()
    test_state_from_booleans()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
