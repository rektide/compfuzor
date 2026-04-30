#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'filter_plugins'))

from subsystem_bypass import (
    _effective_bypass_vars,
    owner_group_fields,
    subsystem_bypassed,
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


# --- _effective_bypass_vars ---


def test_effective_bypass_vars_none():
    print("\n_effective_bypass_vars: None bypass_vars")
    result = _effective_bypass_vars("my_subsystem")
    check("None bypass_vars gives defaults", result, ["MY_SUBSYSTEM_BYPASS"])


def test_effective_bypass_vars_true():
    print("\n_effective_bypass_vars: True bypass_vars")
    result = _effective_bypass_vars("my_subsystem", bypass_vars=True)
    check("True gives defaults", result, ["MY_SUBSYSTEM_BYPASS"])


def test_effective_bypass_vars_false():
    print("\n_effective_bypass_vars: False bypass_vars")
    result = _effective_bypass_vars("my_subsystem", bypass_vars=False)
    check("False gives empty list", result, [])


def test_effective_bypass_vars_string_true():
    print("\n_effective_bypass_vars: 'true' string")
    result = _effective_bypass_vars("my_subsystem", bypass_vars="true")
    check("'true' string gives defaults", result, ["MY_SUBSYSTEM_BYPASS"])


def test_effective_bypass_vars_arbitrary_string():
    print("\n_effective_bypass_vars: arbitrary string")
    result = _effective_bypass_vars("my_subsystem", bypass_vars="SOME_VAR")
    check("arbitrary string normalized", result, ["SOME_VAR_BYPASS"])


def test_effective_bypass_vars_list_without_true():
    print("\n_effective_bypass_vars: list without True")
    result = _effective_bypass_vars("my_subsystem", bypass_vars=["EXTRA"])
    check("list without True is replacement", result, ["EXTRA_BYPASS"])


def test_effective_bypass_vars_list_with_true():
    print("\n_effective_bypass_vars: list with True")
    result = _effective_bypass_vars("my_subsystem", bypass_vars=[True, "EXTRA"])
    check("list with True gives defaults + supplement", result, ["MY_SUBSYSTEM_BYPASS", "EXTRA_BYPASS"])


def test_effective_bypass_vars_domain():
    print("\n_effective_bypass_vars: domain adds second default")
    result = _effective_bypass_vars("my_subsystem", domain="my_domain")
    check("domain adds domain bypass var", result, ["MY_SUBSYSTEM_BYPASS", "MY_DOMAIN_BYPASS"])


def test_effective_bypass_vars_domain_with_true_list():
    print("\n_effective_bypass_vars: list with True + domain")
    result = _effective_bypass_vars("my_subsystem", bypass_vars=[True, "EXTRA"], domain="my_domain")
    check("domain defaults + supplement", result, ["MY_SUBSYSTEM_BYPASS", "MY_DOMAIN_BYPASS", "EXTRA_BYPASS"])


# --- owner_group_fields ---


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


# --- subsystem_bypassed ---


def test_subsystem_bypassed_truthy():
    print("\nsubsystem_bypassed: bypass var is truthy")
    ctx = {"vars": {"MY_SUBSYSTEM_BYPASS": True}}
    result = subsystem_bypassed(ctx, "my_subsystem")
    check("returns True when bypass var truthy", result, True)


def test_subsystem_bypassed_falsy():
    print("\nsubsystem_bypassed: bypass var is falsy")
    ctx = {"vars": {"MY_SUBSYSTEM_BYPASS": False}}
    result = subsystem_bypassed(ctx, "my_subsystem")
    check("returns False when bypass var falsy", result, False)


def test_subsystem_bypassed_absent():
    print("\nsubsystem_bypassed: bypass var absent")
    ctx = {"vars": {}}
    result = subsystem_bypassed(ctx, "my_subsystem")
    check("returns False when bypass var absent", result, False)


def test_subsystem_bypassed_custom_var():
    print("\nsubsystem_bypassed: custom bypass var truthy")
    ctx = {"vars": {"CUSTOM_BYPASS": True}}
    result = subsystem_bypassed(ctx, "my_subsystem", bypass_vars="CUSTOM")
    check("returns True for custom bypass var", result, True)


if __name__ == "__main__":
    test_effective_bypass_vars_none()
    test_effective_bypass_vars_true()
    test_effective_bypass_vars_false()
    test_effective_bypass_vars_string_true()
    test_effective_bypass_vars_arbitrary_string()
    test_effective_bypass_vars_list_without_true()
    test_effective_bypass_vars_list_with_true()
    test_effective_bypass_vars_domain()
    test_effective_bypass_vars_domain_with_true_list()

    test_owner_group_fields_row_provides()
    test_owner_group_fields_fallback_to_context()
    test_owner_group_fields_empty_dropped()
    test_owner_group_fields_no_context_vars()
    test_owner_group_fields_explicit_args()

    test_subsystem_bypassed_truthy()
    test_subsystem_bypassed_falsy()
    test_subsystem_bypassed_absent()
    test_subsystem_bypassed_custom_var()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
