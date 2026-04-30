#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'library', 'filter_plugins'))

from subsystem_rollup import subsystem_rollup

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


EMPTY = {"ETC_FILES": [], "BINS": [], "ENV": {}, "ENV_LIST": [], "PKGS": []}


def test_rollup_multiple_children():
    print("\nsubsystem_rollup: multiple children with contrib")
    children = [
        {"contrib": {"BINS": [{"name": "build.sh"}], "PKGS": ["pkg1"]}},
        {"contrib": {"BINS": [{"name": "install.sh"}], "PKGS": ["pkg2"]}},
    ]
    result = subsystem_rollup(children)
    expected = {
        "ETC_FILES": [],
        "BINS": [{"name": "build.sh"}, {"name": "install.sh"}],
        "ENV": {},
        "ENV_LIST": [],
        "PKGS": ["pkg1", "pkg2"],
    }
    check("appends BINS and PKGS from both children", result, expected)


def test_rollup_child_without_contrib():
    print("\nsubsystem_rollup: child without contrib key uses child directly")
    children = [
        {"BINS": [{"name": "direct.sh"}], "PKGS": ["direct_pkg"]},
    ]
    result = subsystem_rollup(children)
    expected = {
        "ETC_FILES": [],
        "BINS": [{"name": "direct.sh"}],
        "ENV": {},
        "ENV_LIST": [],
        "PKGS": ["direct_pkg"],
    }
    check("child dict used as payload", result, expected)


def test_rollup_mixed_contrib_and_direct():
    print("\nsubsystem_rollup: mixed contrib and direct children")
    children = [
        {"contrib": {"BINS": [{"name": "a.sh"}]}},
        {"BINS": [{"name": "b.sh"}]},
    ]
    result = subsystem_rollup(children)
    expected = {
        "ETC_FILES": [],
        "BINS": [{"name": "a.sh"}, {"name": "b.sh"}],
        "ENV": {},
        "ENV_LIST": [],
        "PKGS": [],
    }
    check("both styles merged", result, expected)


def test_rollup_aggregate():
    print("\nsubsystem_rollup: aggregate overlay")
    children = [{"contrib": {"BINS": [{"name": "child.sh"}], "PKGS": ["pkg1"]}}]
    aggregate = {"BINS": [{"name": "agg.sh"}], "PKGS": ["pkg1", "pkg_agg"]}
    result = subsystem_rollup(children, aggregate=aggregate)
    expected = {
        "ETC_FILES": [],
        "BINS": [{"name": "child.sh"}, {"name": "agg.sh"}],
        "ENV": {},
        "ENV_LIST": [],
        "PKGS": ["pkg1", "pkg_agg"],  # append_unique dedupes pkg1
    }
    check("aggregate appended after children", result, expected)


def test_rollup_include_aggregate_false():
    print("\nsubsystem_rollup: include_aggregate=False")
    children = [{"contrib": {"BINS": [{"name": "child.sh"}]}}]
    aggregate = {"BINS": [{"name": "agg.sh"}]}
    result = subsystem_rollup(children, aggregate=aggregate, include_aggregate=False)
    expected = {
        "ETC_FILES": [],
        "BINS": [{"name": "child.sh"}],
        "ENV": {},
        "ENV_LIST": [],
        "PKGS": [],
    }
    check("aggregate excluded", result, expected)


def test_rollup_empty_children():
    print("\nsubsystem_rollup: empty children list")
    result = subsystem_rollup([])
    check("empty children yields empty result", result, EMPTY)


def test_rollup_single_child():
    print("\nsubsystem_rollup: single child")
    children = [{"contrib": {"BINS": [{"name": "only.sh"}], "ENV": {"FOO": "bar"}}}]
    result = subsystem_rollup(children)
    expected = {
        "ETC_FILES": [],
        "BINS": [{"name": "only.sh"}],
        "ENV": {"FOO": "bar"},
        "ENV_LIST": [],
        "PKGS": [],
    }
    check("single child contrib merged", result, expected)


def test_rollup_dict_overlay():
    print("\nsubsystem_rollup: ENV dict_overlay, later wins")
    children = [
        {"contrib": {"ENV": {"A": "1", "B": "first"}}},
        {"contrib": {"ENV": {"B": "second", "C": "3"}}},
    ]
    result = subsystem_rollup(children)
    expected = {
        "ETC_FILES": [],
        "BINS": [],
        "ENV": {"A": "1", "B": "second", "C": "3"},
        "ENV_LIST": [],
        "PKGS": [],
    }
    check("ENV merged with later winning", result, expected)


def test_rollup_append_unique_dedupes():
    print("\nsubsystem_rollup: PKGS append_unique dedupes")
    children = [
        {"contrib": {"PKGS": ["pkg1", "pkg2"]}},
        {"contrib": {"PKGS": ["pkg2", "pkg3"]}},
    ]
    result = subsystem_rollup(children)
    expected = {
        "ETC_FILES": [],
        "BINS": [],
        "ENV": {},
        "ENV_LIST": [],
        "PKGS": ["pkg1", "pkg2", "pkg3"],
    }
    check("PKGS deduped preserving order", result, expected)


if __name__ == "__main__":
    test_rollup_multiple_children()
    test_rollup_child_without_contrib()
    test_rollup_mixed_contrib_and_direct()
    test_rollup_aggregate()
    test_rollup_include_aggregate_false()
    test_rollup_empty_children()
    test_rollup_single_child()
    test_rollup_dict_overlay()
    test_rollup_append_unique_dedupes()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
