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
        check("raised ValueError", "unknown" in str(e).lower(), True)


def test_validate_unknown_string_strategy():
    print("\nvalidate unknown string strategy:")

    try:
        merge_with_strategy([{"a": 1}], {"a": "nope"})
        check("should have raised", False, True)
    except ValueError as e:
        msg = str(e)
        check("mentions strategy name", "nope" in msg, True)
        check("mentions field path", "'a'" in msg, True)


def test_validate_unknown_operation():
    print("\nvalidate unknown operation:")

    try:
        merge_with_strategy([{"a": 1}], {"a": {"op": "bogus_op"}})
        check("should have raised", False, True)
    except ValueError as e:
        msg = str(e)
        check("mentions op name", "bogus_op" in msg, True)
        check("mentions field path", "'a'" in msg, True)


def test_validate_nested_unknown():
    print("\nvalidate nested unknown strategy:")

    try:
        merge_with_strategy(
            [{"outer": {"inner": 1}}],
            {"outer": {"inner": "bad_strategy"}},
        )
        check("should have raised", False, True)
    except ValueError as e:
        msg = str(e)
        check("mentions strategy name", "bad_strategy" in msg, True)
        check("mentions nested path", "outer.inner" in msg, True)


def test_validate_non_string_non_dict():
    print("\nvalidate non-string non-dict strategy:")

    try:
        merge_with_strategy([{"a": 1}], {"a": 42})
        check("should have raised", False, True)
    except ValueError as e:
        msg = str(e)
        check("mentions type", "int" in msg, True)
        check("mentions field path", "'a'" in msg, True)


def test_validate_valid_strategies_pass():
    print("\nvalidate valid strategies pass:")
    try:
        merge_with_strategy(
            [{"a": [1]}],
            {"a": "append"},
        )
        check("append accepted", True, True)
    except ValueError:
        check("append accepted", False, True)

    try:
        merge_with_strategy(
            [{"a": [1, 2]}],
            {"a": "append_unique"},
        )
        check("append_unique accepted", True, True)
    except ValueError:
        check("append_unique accepted", False, True)

    try:
        merge_with_strategy(
            [{"a": {"x": 1}}],
            {"a": "dict_overlay"},
        )
        check("dict_overlay accepted", True, True)
    except ValueError:
        check("dict_overlay accepted", False, True)

    try:
        merge_with_strategy(
            [{"a": "val"}],
            {"a": "replace"},
        )
        check("replace accepted", True, True)
    except ValueError:
        check("replace accepted", False, True)


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
    test_validate_unknown_string_strategy()
    test_validate_unknown_operation()
    test_validate_nested_unknown()
    test_validate_non_string_non_dict()
    test_validate_valid_strategies_pass()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
