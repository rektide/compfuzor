#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'filter_plugins'))

from subsystem_bypass import owner_group_fields

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


def test_owner_group_fields_row_provides():
    print("\nowner_group_fields: row provides owner/group")
    ctx = {"vars": {"OWNER": "root", "GROUP": "root"}}
    result = owner_group_fields(ctx, {"owner": "www", "group": "www"})
    check("row values used", result, {"owner": "www", "group": "www"})


def test_owner_group_fields_fallback_to_context():
    print("\nowner_group_fields: fallback to context vars")
    ctx = {"vars": {"OWNER": "root", "GROUP": "root"}}
    result = owner_group_fields(ctx, {})
    check("context vars used as fallback", result, {"owner": "root", "group": "root"})


def test_owner_group_fields_empty_dropped():
    print("\nowner_group_fields: empty values dropped")
    ctx = {"vars": {"OWNER": "root", "GROUP": "root"}}
    result = owner_group_fields(ctx, {"owner": ""})
    check("empty owner dropped, group from context", result, {"group": "root"})


def test_owner_group_fields_no_context_vars():
    print("\nowner_group_fields: no context vars, empty row")
    ctx = {"vars": {}}
    result = owner_group_fields(ctx, {})
    check("no values yields empty dict", result, {})


def test_owner_group_fields_explicit_args():
    print("\nowner_group_fields: explicit owner/group args")
    ctx = {"vars": {"OWNER": "root", "GROUP": "root"}}
    result = owner_group_fields(ctx, {}, owner="admin", group="admin")
    check("explicit args used", result, {"owner": "admin", "group": "admin"})


if __name__ == "__main__":
    test_owner_group_fields_row_provides()
    test_owner_group_fields_fallback_to_context()
    test_owner_group_fields_empty_dropped()
    test_owner_group_fields_no_context_vars()
    test_owner_group_fields_explicit_args()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
