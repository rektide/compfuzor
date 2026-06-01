#!/usr/bin/env python3

import os
import sys

from jinja2 import Undefined

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "library", "filter_plugins"
    ),
)

from ansible.errors import AnsibleFilterError

from dictify import dictify

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


def test_mapping_passes_through():
    print("\ndictify mapping:")
    check("mapping copied", dictify({"rust": True}), {"rust": True})


def test_list_of_strings_becomes_true_mapping():
    print("\ndictify string list:")
    check("strings become true values", dictify(["rust", "nodejs"]), {"rust": True, "nodejs": True})


def test_list_mappings_overlay():
    print("\ndictify mapping list:")
    check("mappings overlay", dictify([{"rust": True}, {"rust": "1.88"}, "nodejs"]), {"rust": "1.88", "nodejs": True})


def test_undefined_and_none_empty():
    print("\ndictify empty values:")
    check("undefined becomes empty", dictify(Undefined(name="missing")), {})
    check("none becomes empty", dictify(None), {})


def test_scalar_raises():
    print("\ndictify scalar:")
    try:
        dictify("rust")
        check("should have raised", False, True)
    except AnsibleFilterError as e:
        check("rejects scalar string", "mapping or list-like" in str(e), True)


def test_bad_list_item_raises():
    print("\ndictify bad list item:")
    try:
        dictify(["rust", 3])
        check("should have raised", False, True)
    except AnsibleFilterError as e:
        check("rejects non-string list item", "strings or mappings" in str(e), True)


if __name__ == "__main__":
    test_mapping_passes_through()
    test_list_of_strings_becomes_true_mapping()
    test_list_mappings_overlay()
    test_undefined_and_none_empty()
    test_scalar_raises()
    test_bad_list_item_raises()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
