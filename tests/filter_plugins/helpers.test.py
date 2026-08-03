#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from helpers import HELPERS_DESCRIPTIONS, helper_comment, resolve_helpers  # noqa: E402


DEFAULT = ["env", "setopts", "loud"]


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def resolve_bin_helpers(item, default_helpers=DEFAULT):
    """Mirror the explicit caller-side policy in files/_bin."""
    if item.get("helpers") is False:
        return []
    layers = [
        default_helpers,
        item.get("base_helpers"),
        ["report", "guard"] if item.get("bypass") is not False and "bypass" in item else None,
        item.get("helpers"),
    ]
    return resolve_helpers(layers)


def test_plain_bin_gets_default():
    check("plain bin", resolve_bin_helpers({}), DEFAULT)


def test_bypass_is_a_caller_layer():
    check(
        "bypass adds report and guard",
        resolve_bin_helpers({"bypass": "KERNEL"}),
        ["env", "setopts", "loud", "report", "guard"],
    )
    check(
        "bypass False adds no layer",
        resolve_bin_helpers({"bypass": False}),
        DEFAULT,
    )


def test_helpers_false_is_only_nuclear_signal():
    check("helpers False nuclear", resolve_bin_helpers({"helpers": False}), [])
    check(
        "helpers False beats bypass and base helpers",
        resolve_bin_helpers(
            {"helpers": False, "bypass": "KERNEL", "base_helpers": ["guard"]}
        ),
        [],
    )
    check(
        "no_header is ordinary ignored data",
        resolve_bin_helpers({"no_header": True}),
        DEFAULT,
    )


def test_base_and_author_layers_remain_explicit():
    check(
        "base helpers False suppresses only its layer",
        resolve_bin_helpers({"base_helpers": False}),
        DEFAULT,
    )
    check(
        "base and author layers merge in canonical order",
        resolve_bin_helpers({"base_helpers": ["report"], "helpers": ["guard"]}),
        ["env", "setopts", "loud", "report", "guard"],
    )
    check(
        "report implies loud without a loud default",
        resolve_bin_helpers({"helpers": "report"}, default_helpers=["env"]),
        ["env", "loud", "report"],
    )


def test_unknown_helper_names_are_dropped_by_the_preset():
    check(
        "unknown helper names dropped",
        resolve_helpers([["bogus", "env"]]),
        ["env"],
    )


def test_helper_comment_formats():
    check(
        "helper_comment with description",
        helper_comment("env"),
        "# env helper: " + HELPERS_DESCRIPTIONS["env"],
    )
    check(
        "helper_comment loud",
        helper_comment("loud"),
        "# loud helper: " + HELPERS_DESCRIPTIONS["loud"],
    )


if __name__ == "__main__":
    test_plain_bin_gets_default()
    test_bypass_is_a_caller_layer()
    test_helpers_false_is_only_nuclear_signal()
    test_base_and_author_layers_remain_explicit()
    test_unknown_helper_names_are_dropped_by_the_preset()
    test_helper_comment_formats()
