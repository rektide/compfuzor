#!/usr/bin/env python3

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from merge_strategy import merge_with_strategy

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


def test_append():
    print("\nappend strategy:")
    result = merge_with_strategy(
        [{"a": [1]}, {"a": [2]}, {"a": [3]}],
        {"a": "append"},
    )
    check("appends all values", result, {"a": [1, 2, 3]})


def test_append_unique():
    print("\nappend_unique strategy:")
    result = merge_with_strategy(
        [{"a": [1, 2]}, {"a": [2, 3]}],
        {"a": "append_unique"},
    )
    check("dedupes preserving order", result, {"a": [1, 2, 3]})


def test_dict_overlay():
    print("\ndict_overlay strategy:")
    result = merge_with_strategy(
        [{"a": {"x": 1}}, {"a": {"y": 2}}, {"a": {"x": 3}}],
        {"a": "dict_overlay"},
    )
    check("later wins, merges keys", result, {"a": {"x": 3, "y": 2}})


def test_replace():
    print("\nreplace strategy:")
    result = merge_with_strategy(
        [{"a": "first"}, {"a": "second"}, {"a": None}],
        {"a": "replace"},
    )
    check("latest non-None wins", result, {"a": "second"})


def test_nested_strategy():
    print("\nnested strategy map:")
    result = merge_with_strategy(
        [
            {"outer": {"inner_a": [1], "inner_b": "x"}},
            {"outer": {"inner_a": [2], "inner_b": "y"}},
        ],
        {"outer": {"inner_a": "append", "inner_b": "replace"}},
    )
    check(
        "nested append + replace",
        result,
        {"outer": {"inner_a": [1, 2], "inner_b": "y"}},
    )


def test_payload_key():
    print("\npayload_key extraction:")
    result = merge_with_strategy(
        [
            {"contrib": {"BINS": [1]}},
            {"contrib": {"BINS": [2]}},
            {"no_contrib": {"BINS": [99]}},
        ],
        {"BINS": "append"},
        payload_key="contrib",
    )
    check("uses contrib payload only", result, {"BINS": [1, 2]})


def test_aggregate():
    print("\naggregate inclusion:")
    result = merge_with_strategy(
        [{"a": [1]}],
        {"a": "append"},
        aggregate={"a": [2]},
        include_aggregate=True,
    )
    check("aggregate appended", result, {"a": [1, 2]})

    result_no_agg = merge_with_strategy(
        [{"a": [1]}],
        {"a": "append"},
        aggregate={"a": [2]},
        include_aggregate=False,
    )
    check("aggregate excluded", result_no_agg, {"a": [1]})


def test_merge_keyed_operation():
    print("\nmerge_keyed operation strategy:")
    result = merge_with_strategy(
        [
            {"BINS": [{"name": "build.sh", "generated": "echo one"}]},
            {
                "BINS": [
                    {"name": "build.sh", "generated": "echo two"},
                    {"name": "install.sh", "generated": "echo install"},
                ]
            },
        ],
        {"BINS": {"op": "merge_keyed", "key": "name", "concat_fields": ["generated"]}},
    )
    expected = {
        "BINS": [
            {"name": "build.sh", "generated": "echo one\necho two"},
            {"name": "install.sh", "generated": "echo install"},
        ]
    }
    check("keyed merge with concat", result, expected)


def test_merge_keyed_no_overlap():
    print("\nmerge_keyed operation no overlap:")
    result = merge_with_strategy(
        [
            {"BINS": [{"name": "build.sh"}]},
            {"BINS": [{"name": "install.sh"}]},
        ],
        {"BINS": {"op": "merge_keyed", "key": "name"}},
    )
    check(
        "both entries kept",
        result,
        {"BINS": [{"name": "build.sh"}, {"name": "install.sh"}]},
    )


def test_empty_records():
    print("\nempty records:")
    result = merge_with_strategy([], {"a": "append"})
    check("empty input yields initial", result, {"a": []})


def test_unknown_strategy():
    print("\nunknown strategy raises:")
    try:
        merge_with_strategy([{"a": 1}], {"a": "bogus"})
        check("should have raised", False, True)
    except ValueError as e:
        check("raised ValueError", "Unknown" in str(e), True)


if __name__ == "__main__":
    test_append()
    test_append_unique()
    test_dict_overlay()
    test_replace()
    test_nested_strategy()
    test_payload_key()
    test_aggregate()
    test_merge_keyed_operation()
    test_merge_keyed_no_overlap()
    test_empty_records()
    test_unknown_strategy()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
