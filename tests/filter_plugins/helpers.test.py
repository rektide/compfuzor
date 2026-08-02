#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from helpers import resolve_helpers, helper_comment, HELPERS_DESCRIPTIONS  # noqa: E402


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


DEFAULT = ["env", "setopts", "loud"]


def test_plain_bin_gets_default():
    # A bin with no helper-related fields gets exactly DEFAULT_HELPERS,
    # in canonical order.
    check("plain bin", resolve_helpers({}, DEFAULT), DEFAULT)


def test_bypass_implies_report_and_guard_and_loud():
    # bypass behavior needs report+guard; report needs loud. default supplies
    # the rest. Result: all five, canonical order.
    check(
        "bypass implies report+guard+loud",
        resolve_helpers({"bypass": "KERNEL"}, DEFAULT),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_bypass_list_form():
    check(
        "bypass as list",
        resolve_helpers({"bypass": ["ENV", "ENV:ZIMFW"]}, DEFAULT),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_bypass_false_does_not_imply():
    check(
        "bypass False does not imply",
        resolve_helpers({"bypass": False}, DEFAULT),
        DEFAULT,
    )


def test_helpers_false_is_nuclear():
    # helpers: False zeroes everything, regardless of default/base/bypass.
    check("helpers False nuclear", resolve_helpers({"helpers": False}, DEFAULT), [])
    check(
        "helpers False nuclear + bypass",
        resolve_helpers({"helpers": False, "bypass": "KERNEL"}, DEFAULT),
        [],
    )
    check(
        "helpers False nuclear + base_helpers",
        resolve_helpers({"helpers": False, "base_helpers": ["guard"]}, DEFAULT),
        [],
    )


def test_no_header_legacy_is_nuclear():
    check("no_header true nuclear", resolve_helpers({"no_header": True}, DEFAULT), [])


def test_base_helpers_merges_not_overwrites():
    # subsystem contributes report+guard via base_helpers; default still
    # supplies env+setopts+loud. Union, canonical order.
    check(
        "base_helpers merges",
        resolve_helpers({"base_helpers": ["report", "guard"]}, DEFAULT),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_base_helpers_false_suppresses_layer_only():
    # base_helpers: False drops the subsystem layer but default remains.
    check(
        "base_helpers False keeps default",
        resolve_helpers({"base_helpers": False}, DEFAULT),
        DEFAULT,
    )


def test_base_helpers_false_with_bypass():
    # base_helpers False does NOT suppress implications; bypass still adds
    # report+guard.
    check(
        "base_helpers False + bypass keeps implications",
        resolve_helpers({"base_helpers": False, "bypass": "ENV"}, DEFAULT),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_helpers_author_addon_merges():
    check(
        "helpers author addon",
        resolve_helpers({"helpers": ["report"]}, DEFAULT),
        ["env", "setopts", "loud", "report"],
    )


def test_helpers_author_extends_subsystem_base():
    # author asks for guard on top of a subsystem that set base report+guard.
    # Union, no overwrite.
    check(
        "author extends subsystem base",
        resolve_helpers(
            {"base_helpers": ["report"], "helpers": ["guard"]}, DEFAULT
        ),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_scalar_helpers_treated_as_single():
    check(
        "scalar helpers string",
        resolve_helpers({"helpers": "report"}, DEFAULT),
        ["env", "setopts", "loud", "report"],
    )


def test_scalar_base_helpers_treated_as_single():
    check(
        "scalar base_helpers string",
        resolve_helpers({"base_helpers": "guard", "bypass": "ENV"}, DEFAULT),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_canonical_order_independent_of_request_order():
    # Request in reverse canonical order; output must still be canonical.
    check(
        "canonical order enforced",
        resolve_helpers(
            {"helpers": ["guard", "report", "loud", "setopts", "env"]},
            default_helpers=None,
        ),
        ["env", "setopts", "loud", "report", "guard"],
    )


def test_default_helpers_override():
    check(
        "default_helpers override supplied",
        resolve_helpers({}, default_helpers=["env"]),
        ["env"],
    )


def test_default_helpers_none_uses_module_default():
    check(
        "default_helpers None -> module default",
        resolve_helpers({}, default_helpers=None),
        list(DEFAULT),
    )


def test_report_implies_loud_even_without_default():
    # If default were narrowed to drop loud, requesting report pulls loud in.
    check(
        "report implies loud",
        resolve_helpers({"helpers": ["report"]}, default_helpers=["env"]),
        ["env", "loud", "report"],
    )


def test_unknown_helper_names_dropped():
    check(
        "unknown names dropped",
        resolve_helpers({"helpers": ["bogus", "env"]}, default_helpers=[]),
        ["env"],
    )


def test_non_mapping_item():
    check("non-mapping item", resolve_helpers("build.sh", DEFAULT), DEFAULT)


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
    test_bypass_implies_report_and_guard_and_loud()
    test_bypass_list_form()
    test_bypass_false_does_not_imply()
    test_helpers_false_is_nuclear()
    test_no_header_legacy_is_nuclear()
    test_base_helpers_merges_not_overwrites()
    test_base_helpers_false_suppresses_layer_only()
    test_base_helpers_false_with_bypass()
    test_helpers_author_addon_merges()
    test_helpers_author_extends_subsystem_base()
    test_scalar_helpers_treated_as_single()
    test_scalar_base_helpers_treated_as_single()
    test_canonical_order_independent_of_request_order()
    test_default_helpers_override()
    test_default_helpers_none_uses_module_default()
    test_report_implies_loud_even_without_default()
    test_unknown_helper_names_dropped()
    test_non_mapping_item()
    test_helper_comment_formats()
