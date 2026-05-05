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

from ansible._internal._datatag import _tags
from ansible.module_utils._internal._datatag import AnsibleTagHelper

from merge import merge_list

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
    print("\nmerge_list append:")
    result = merge_list([[1], [2], [3]])
    check("appends payloads", result, [1, 2, 3])


def test_append_unique():
    print("\nmerge_list append_unique:")
    result = merge_list([[1, 2], [2, 3]], "append_unique")
    check("dedupes preserving order", result, [1, 2, 3])


def test_single_payload():
    print("\nmerge_list single:")
    result = merge_list([{"name": "build.sh"}, {"name": "install.sh"}], single=True)
    check(
        "single treats list as one payload",
        result,
        [{"name": "build.sh"}, {"name": "install.sh"}],
    )


def test_get_path():
    print("\nmerge_list get:")
    result = merge_list(
        [[{"name": "build.sh"}], [{"name": "install.sh"}]],
        "bins_generated",
        get="1.name",
    )
    check("extracts path from merged list", result, "install.sh")


def test_undefined_is_empty():
    print("\nmerge_list undefined:")
    result = merge_list([Undefined(name="missing"), ["x"]])
    check("undefined payload ignored", result, ["x"])
    check("undefined input is empty", merge_list(Undefined(name="missing")), [])


def test_bins_generated_profile():
    print("\nmerge_list bins_generated:")
    result = merge_list(
        [
            [{"name": "build.sh", "generated": "echo one"}],
            [
                {"name": "build.sh", "generated": "echo two"},
                {"name": "install.sh", "generated": "echo install"},
            ],
        ],
        "bins_generated",
    )
    check(
        "merges by name and concats generated",
        result,
        [
            {"name": "build.sh", "generated": "echo one\necho two"},
            {"name": "install.sh", "generated": "echo install"},
        ],
    )


def test_append_unique_by():
    print("\nmerge_list append_unique_by:")
    result = merge_list(
        [
            [{"name": "a", "v": 1}, {"name": "b", "v": 2}],
            [{"name": "a", "v": 10}, {"name": "c", "v": 3}],
        ],
        {"op": "append_unique_by", "key": "name"},
    )
    check(
        "last keyed item wins",
        result,
        [{"name": "a", "v": 10}, {"name": "b", "v": 2}, {"name": "c", "v": 3}],
    )


def test_concat_preserves_template_tags():
    print("\nmerge_list tag-preserving concat:")
    left = _tags.TrustedAsTemplate().tag("{{ LEFT }}")
    right = _tags.TrustedAsTemplate().tag("{{ RIGHT }}")
    result = merge_list(
        [
            [{"name": "build.sh", "generated": left}],
            [{"name": "build.sh", "generated": right}],
        ],
        "bins_generated",
    )
    generated = result[0]["generated"]
    check("concats tagged strings", generated, "{{ LEFT }}\n{{ RIGHT }}")
    check(
        "preserves TrustedAsTemplate tag",
        _tags.TrustedAsTemplate() in AnsibleTagHelper.tags(generated),
        True,
    )


class FakeLazyList(list):
    def __iter__(self):
        raise AssertionError("lazy list rendered")

    def _non_lazy_copy(self):
        return [item for item in list.__iter__(self)]


def test_non_lazy_copy_boundary():
    print("\nmerge_list raw-copy boundary:")
    result = merge_list(FakeLazyList([["a"], ["b"]]))
    check("uses _non_lazy_copy before iterating", result, ["a", "b"])


def test_unknown_strategy_raises():
    print("\nmerge_list unknown strategy:")
    try:
        merge_list([], "bogus")
        check("should have raised", False, True)
    except ValueError as e:
        check("mentions unknown strategy", "bogus" in str(e), True)


if __name__ == "__main__":
    test_append()
    test_append_unique()
    test_single_payload()
    test_get_path()
    test_undefined_is_empty()
    test_bins_generated_profile()
    test_append_unique_by()
    test_concat_preserves_template_tags()
    test_non_lazy_copy_boundary()
    test_unknown_strategy_raises()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
