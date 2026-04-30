#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'filter_plugins'))

from jinja2 import Undefined

from concat2 import concat2

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


def test_both_lists():
    print("\nboth lists:")
    result = concat2([1, 2], [3, 4])
    check("concatenated", result, [1, 2, 3, 4])


def test_left_none():
    print("\nleft is None:")
    result = concat2(None, [3, 4])
    check("right returned as list", result, [3, 4])


def test_right_none():
    print("\nright is None:")
    result = concat2([1, 2], None)
    check("left returned as list", result, [1, 2])


def test_both_none():
    print("\nboth None:")
    result = concat2(None, None)
    check("empty list", result, [])


def test_left_string_right_list():
    print("\nleft is string, right is list:")
    result = concat2("hello", [3, 4])
    check("string wrapped + list", result, ["hello", 3, 4])


def test_unique_deduplicates():
    print("\nunique=True deduplicates:")
    result = concat2([1, 2, 3], [2, 3, 4], unique=True)
    check("order preserved, deduped", result, [1, 2, 3, 4])


def test_unique_no_duplicates():
    print("\nunique=True with no duplicates:")
    result = concat2([1, 2], [3, 4], unique=True)
    check("same as without unique", result, [1, 2, 3, 4])


def test_unique_false_keeps_duplicates():
    print("\nunique=False (default) keeps duplicates:")
    result = concat2([1, 2], [2, 3])
    check("duplicates kept", result, [1, 2, 2, 3])


def test_single_plus_single():
    print("\nsingle value + single value:")
    result = concat2("a", "b")
    check("list of two", result, ["a", "b"])


def test_dict_plus_list():
    print("\ndict + list:")
    result = concat2({"key": "val"}, [1, 2])
    check("dict wrapped + list", result, [{"key": "val"}, 1, 2])


def _make_undefined(name="UNDEF"):
    return Undefined(name=name)


def test_left_undefined():
    print("\nleft is AnsibleUndefined:")
    result = concat2(_make_undefined("ETC_FILES"), [3, 4])
    check("right returned as list", result, [3, 4])


def test_right_undefined():
    print("\nright is AnsibleUndefined:")
    result = concat2([1, 2], _make_undefined("OTHER"))
    check("left returned as list", result, [1, 2])


def test_both_undefined():
    print("\nboth AnsibleUndefined:")
    result = concat2(_make_undefined("A"), _make_undefined("B"))
    check("empty list", result, [])


def test_left_undefined_unique():
    print("\nleft AnsibleUndefined, unique=True:")
    result = concat2(_make_undefined("X"), [2, 3, 2], unique=True)
    check("right returned, deduped", result, [2, 3])


if __name__ == "__main__":
    test_both_lists()
    test_left_none()
    test_right_none()
    test_both_none()
    test_left_string_right_list()
    test_unique_deduplicates()
    test_unique_no_duplicates()
    test_unique_false_keeps_duplicates()
    test_single_plus_single()
    test_dict_plus_list()
    test_left_undefined()
    test_right_undefined()
    test_both_undefined()
    test_left_undefined_unique()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
