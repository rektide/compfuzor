#!/usr/bin/env python3

import os
import sys

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "library", "lookup_plugins"
    ),
)

from vars_list import resolve_list, _iter_var_names as vl_iter
from vars_dict import resolve_dict, _iter_var_names as vd_iter

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


def _make_variables():
    return {
        "FOO": "foo-value",
        "BAR": {"nested": True},
        "VAR_NAMES": ["FOO", "BAR", "MISSING"],
    }


def test_iter_var_names_flattens_lists():
    print("\n_iter_var_names flattens:")
    names = list(vl_iter(["A", ["B", "C"], "D"]))
    check("flattens nested lists", names, ["A", "B", "C", "D"])
    check("same logic in vars_dict", list(vd_iter(["A", ["B", "C"], "D"])), names)


def test_vars_list_resolves_values_and_defaults():
    print("\nvars_list resolves:")
    variables = _make_variables()
    resolved = resolve_list([["FOO", "BAR", "MISSING"]], variables, default="__missing__")
    check("FOO resolved", resolved[0], "foo-value")
    check("BAR resolved nested", resolved[1], {"nested": True})
    check("MISSING uses default", resolved[2], "__missing__")


def test_vars_dict_resolves_values_and_defaults():
    print("\nvars_dict resolves:")
    variables = _make_variables()
    resolved = resolve_dict([["FOO", "BAR", "MISSING"]], variables, default="__missing__")
    check("FOO key", resolved["FOO"], "foo-value")
    check("BAR key nested", resolved["BAR"], {"nested": True})
    check("MISSING key default", resolved["MISSING"], "__missing__")


def test_vars_list_explicit_names():
    print("\nvars_list explicit names:")
    variables = {"X": 1, "Y": 2}
    resolved = resolve_list(["X", "Y"], variables)
    check("explicit string terms", resolved, [1, 2])


def test_vars_dict_explicit_names():
    print("\nvars_dict explicit names:")
    variables = {"X": 1, "Y": 2}
    resolved = resolve_dict(["X", "Y"], variables)
    check("explicit string terms", resolved, {"X": 1, "Y": 2})


if __name__ == "__main__":
    test_iter_var_names_flattens_lists()
    test_vars_list_resolves_values_and_defaults()
    test_vars_dict_resolves_values_and_defaults()
    test_vars_list_explicit_names()
    test_vars_dict_explicit_names()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
