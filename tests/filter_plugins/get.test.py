#!/usr/bin/env python3

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'filter_plugins'))

from jinja2 import Undefined

from get import get

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


def _undef(name="UNDEF"):
    return Undefined(name=name)


def test_dict_path():
    print("\ndict path:")
    value = {"a": {"b": {"c": 7}}}
    check("nested value", get(value, "a.b.c", 0), 7)


def test_missing_key_returns_default():
    print("\nmissing key:")
    value = {"a": {"b": 1}}
    check("missing returns default", get(value, "a.x", "fallback"), "fallback")


def test_list_index_path():
    print("\nlist index:")
    value = {"items": [{"name": "x"}, {"name": "y"}]}
    check("index traversal", get(value, "items.1.name", "n/a"), "y")


def test_list_index_out_of_range():
    print("\nlist index out of range:")
    value = {"items": [1]}
    check("out of range default", get(value, "items.3", 9), 9)


def test_none_mid_path():
    print("\nnone in path:")
    value = {"a": None}
    check("none returns default", get(value, "a.b", "fallback"), "fallback")


def test_undefined_input():
    print("\nundefined input:")
    check("undefined returns default", get(_undef("X"), "a.b", "fallback"), "fallback")


def test_undefined_leaf():
    print("\nundefined leaf:")
    value = {"a": _undef("LEAF")}
    check("undefined leaf default", get(value, "a", "fallback"), "fallback")


def test_empty_path_returns_value():
    print("\nempty path:")
    value = {"x": 1}
    check("empty path identity", get(value, "", "fallback"), value)


def test_none_path_returns_value():
    print("\nnone path:")
    value = {"x": 1}
    check("none path identity", get(value, None, "fallback"), value)


if __name__ == "__main__":
    test_dict_path()
    test_missing_key_returns_default()
    test_list_index_path()
    test_list_index_out_of_range()
    test_none_mid_path()
    test_undefined_input()
    test_undefined_leaf()
    test_empty_path_returns_value()
    test_none_path_returns_value()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
