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

from merge import merge_dict, merge_dict_subsys, merge_list, merge_list_subsys

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


class FakeLazyDict(dict):
    def __getitem__(self, key):
        raise AssertionError("lazy dict rendered")

    def get(self, key, default=None):
        raise AssertionError("lazy dict rendered")

    def items(self):
        raise AssertionError("lazy dict rendered")

    def _non_lazy_copy(self):
        return {key: value for key, value in dict.items(self)}


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


def test_merge_dict_overlay():
    print("\nmerge_dict overlay:")
    result = merge_dict([{"PATH": "/a", "KEEP": "old"}, {"PATH": "/b"}])
    check("later dict wins", result, {"PATH": "/b", "KEEP": "old"})


def test_merge_dict_single_and_get():
    print("\nmerge_dict single and get:")
    result = merge_dict({"ENV": {"PATH": "/a"}}, single=True, get="ENV.PATH")
    check("single treats dict as one payload and extracts path", result, "/a")


def test_merge_dict_undefined_is_empty():
    print("\nmerge_dict undefined:")
    result = merge_dict([Undefined(name="missing"), {"PATH": "/a"}])
    check("undefined payload ignored", result, {"PATH": "/a"})
    check("undefined input is empty", merge_dict(Undefined(name="missing")), {})


def test_merge_dict_tool_versions_overlay():
    print("\nmerge_dict tool_versions_overlay:")
    result = merge_dict(
        [
            ["rust", "nodejs"],
            {"rust": "1.88", "pnpm": True},
        ],
        "tool_versions_overlay",
    )
    check("normalizes list and overlays mapping", result, {"rust": "1.88", "nodejs": True, "pnpm": True})


def test_merge_dict_raw_copy_boundary():
    print("\nmerge_dict raw-copy boundary:")
    result = merge_dict(FakeLazyList([{"A": 1}, {"B": 2}]))
    check("uses _non_lazy_copy before iterating", result, {"A": 1, "B": 2})


def test_merge_list_subsys_default_bins():
    print("\nmerge_list_subsys default bins:")
    context = {
        "vars": {
            "SUBSYSTEM": {
                "python": {
                    "active": True,
                    "contrib": {
                        "BINS": [
                            {"name": "build.sh", "generated": "echo python"}
                        ]
                    },
                }
            }
        }
    }
    result = merge_list_subsys(
        context,
        [{"name": "build.sh", "generated": "echo base"}],
        "python",
    )
    check(
        "merges active subsystem bins",
        result,
        [{"name": "build.sh", "generated": "echo base\necho python"}],
    )


def test_merge_list_subsys_inactive_skips():
    print("\nmerge_list_subsys inactive:")
    context = {
        "vars": {
            "SUBSYSTEM": {
                "python": {
                    "active": False,
                    "contrib": {"BINS": [{"name": "build.sh", "generated": "nope"}]},
                }
            }
        }
    }
    result = merge_list_subsys(
        context,
        [{"name": "build.sh", "generated": "echo base"}],
        "python",
    )
    check(
        "skips inactive subsystem by default",
        result,
        [{"name": "build.sh", "generated": "echo base"}],
    )


def test_merge_list_subsys_fallback_and_get():
    print("\nmerge_list_subsys fallback and get:")
    context = {
        "vars": {
            "SUBSYSTEM": {
                "fallback": {
                    "active": True,
                    "contrib": {"BINS": [{"name": "install.sh"}]},
                }
            }
        }
    }
    result = merge_list_subsys(
        context,
        [],
        id="",
        fallback_id="fallback",
        get="0.name",
    )
    check("uses fallback id and extracts result path", result, "install.sh")


def test_merge_list_subsys_raw_copy_boundary():
    print("\nmerge_list_subsys raw-copy boundary:")
    context = {
        "vars": {
            "SUBSYSTEM": FakeLazyDict(
                {
                    "python": {
                        "active": True,
                        "contrib": {"BINS": [{"name": "build.sh"}]},
                    }
                }
            )
        }
    }
    result = merge_list_subsys(context, [], "python")
    check("uses _non_lazy_copy for SUBSYSTEM", result, [{"name": "build.sh"}])


def test_merge_dict_subsys_default_env_current_wins():
    print("\nmerge_dict_subsys default env:")
    context = {
        "vars": {
            "SUBSYSTEM": {
                "python": {
                    "active": True,
                    "contrib": {"ENV": {"PATH": "/sub", "PYTHON_BIN": "python"}},
                }
            }
        }
    }
    result = merge_dict_subsys(context, {"PATH": "/current"}, "python")
    check(
        "current/global env wins by default",
        result,
        {"PATH": "/current", "PYTHON_BIN": "python"},
    )


def test_merge_dict_subsys_incoming_can_win():
    print("\nmerge_dict_subsys incoming wins:")
    context = {
        "vars": {
            "SUBSYSTEM": {
                "python": {
                    "active": True,
                    "contrib": {"ENV": {"PATH": "/sub"}},
                }
            }
        }
    }
    result = merge_dict_subsys(
        context,
        {"PATH": "/current"},
        "python",
        current_wins=False,
    )
    check("subsystem env wins when requested", result, {"PATH": "/sub"})


def test_merge_dict_subsys_inactive_skips():
    print("\nmerge_dict_subsys inactive:")
    context = {
        "vars": {
            "SUBSYSTEM": {
                "python": {
                    "active": False,
                    "contrib": {"ENV": {"PATH": "/sub"}},
                }
            }
        }
    }
    result = merge_dict_subsys(context, {"PATH": "/current"}, "python")
    check("skips inactive subsystem by default", result, {"PATH": "/current"})


def test_merge_dict_subsys_raw_copy_boundary():
    print("\nmerge_dict_subsys raw-copy boundary:")
    context = {
        "vars": {
            "SUBSYSTEM": FakeLazyDict(
                {
                    "python": {
                        "active": True,
                        "contrib": {"ENV": {"PYTHON_BIN": "python"}},
                    }
                }
            )
        }
    }
    result = merge_dict_subsys(context, {}, "python")
    check("uses _non_lazy_copy for SUBSYSTEM", result, {"PYTHON_BIN": "python"})


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
    test_merge_dict_overlay()
    test_merge_dict_single_and_get()
    test_merge_dict_undefined_is_empty()
    test_merge_dict_tool_versions_overlay()
    test_merge_dict_raw_copy_boundary()
    test_merge_list_subsys_default_bins()
    test_merge_list_subsys_inactive_skips()
    test_merge_list_subsys_fallback_and_get()
    test_merge_list_subsys_raw_copy_boundary()
    test_merge_dict_subsys_default_env_current_wins()
    test_merge_dict_subsys_incoming_can_win()
    test_merge_dict_subsys_inactive_skips()
    test_merge_dict_subsys_raw_copy_boundary()

    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
