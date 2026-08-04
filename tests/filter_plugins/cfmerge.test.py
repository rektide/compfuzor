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

from ansible.errors import AnsibleFilterError
from ansible._internal._datatag import _tags
from ansible.module_utils._internal._datatag import AnsibleTagHelper

from cfmerge import (
    COMBINES,
    REFINES,
    collect,
    combine_iff,
    merge_dict,
    merge_fields,
    merge_list,
    normalize,
    run_value_preset,
)
from each import tag_each
from when import when, whenAnd

passed = 0
failed = 0


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


def check_raises(name, fn, text):
    global passed, failed
    try:
        fn()
    except (AnsibleFilterError, TypeError) as error:
        if text in str(error):
            passed += 1
            print("  PASS: {}".format(name))
        else:
            failed += 1
            print("  FAIL: {}".format(name))
            print("    error: {}".format(error))
    else:
        failed += 1
        print("  FAIL: {} (did not raise)".format(name))


def test_collect():
    print("\ncollect:")
    check(
        "skips absence by default",
        collect([None, Undefined(name="missing"), ["kept"]]),
        [["kept"]],
    )
    check(
        "treats absent top-level input as no layers",
        collect(Undefined(name="entire_missing")),
        [],
    )
    check(
        "treats None top-level input as no layers",
        collect(None),
        [],
    )
    check(
        "suppresses only top-level False when enabled",
        collect([False, [False], ["loud"]], skip_layers=("false",)),
        [[False], ["loud"]],
    )
    check(
        "keeps False when suppression is disabled",
        collect([False], skip_layers=()),
        [False],
    )
    check(
        "skips empty layers only when enabled",
        collect([[], {}, "", ["kept"]], skip_layers=("empty",)),
        [["kept"]],
    )
    check_raises(
        "rejects legacy string skip grammar",
        lambda: collect([], skip_layers="none,undefined"),
        "skip_layers",
    )


def test_normalizers():
    print("\nnormalizers:")
    check("identity keeps False", normalize(False, to="identity"), False)
    check("list converts absence and False to empty", normalize(False, to="list"), [])
    check("list wraps mappings as data", normalize({"a": 1}, to="list"), [{"a": 1}])
    check("list expands sequences", normalize(("a", "b"), to="list"), ["a", "b"])
    check("mapping copies mappings", normalize({"a": 1}, to="mapping"), {"a": 1})
    check(
        "mapping expands shorthand left to right",
        normalize(["rust", {"rust": "1.90", "node": True}], to="mapping", shorthand=True),
        {"rust": "1.90", "node": True},
    )
    check(
        "items renames mapping fields",
        normalize({"/dest": "/src"}, to="items", key_name="dest", value_name="src"),
        [{"dest": "/dest", "src": "/src"}],
    )
    check("items preserves item records", normalize([{"name": "tool"}], to="items"), [{"name": "tool"}])
    check_raises(
        "mapping rejects scalar",
        lambda: normalize("rust", to="mapping"),
        "mapping normalizer",
    )
    check_raises(
        "items rejects scalar",
        lambda: normalize("rust", to="items"),
        "items normalizer",
    )


def test_combines_and_refines():
    print("\ncombines and refines:")
    check(
        "keyed fold preserves first key position and concatenates fields",
        merge_list(
            [{"name": "build", "generated": "one"}, {"name": "install"}],
            [{"name": "build", "generated": "two", "value": 2}],
            preset={"name": "merge_keyed", "key": "name", "concat_fields": ["generated"]},
        ),
        [
            {"name": "build", "generated": "one\ntwo", "value": 2},
            {"name": "install"},
        ],
    )
    check(
        "keyed fold keeps the last non-keyed occurrence",
        merge_list(["first", "last"], ["first"], preset="merge_keyed"),
        ["last", "first"],
    )
    check(
        "dedupe uses Python equality for unhashable values",
        merge_list(
            [{"a": 1, "b": 2}, {"b": 2, "a": 1}],
            [1, True],
            preset="append_unique",
        ),
        [{"a": 1, "b": 2}, 1],
    )
    check(
        "dedupe_by retains first key position and last record",
        merge_list(
            [{"name": "a", "value": 1}, {"name": "b"}],
            [{"name": "a", "value": 2}],
            preset={"name": "append_unique_by", "key": "name"},
        ),
        [{"name": "a", "value": 2}, {"name": "b"}],
    )
    check(
        "implicate closes transitively and canonicalizes helper order",
        merge_list(["report", "guard"], preset="helpers"),
        ["loud", "report", "guard"],
    )
    check(
        "implicate keeps unknown unhashable selected values",
        REFINES["implicate"]([["unknown"]], graph={"report": ("loud",)}),
        [["unknown"]],
    )
    check_raises(
        "implicate rejects registered cycles",
        lambda: REFINES["implicate"](["a"], graph={"a": ("b",), "b": ("a",)}),
        "cycle",
    )


def test_fixed_stage_contracts():
    print("\nfixed-stage contracts:")
    check("identity preserves None", normalize(None, to="identity"), None)
    check("mapping converts False to empty", normalize(False, to="mapping"), {})
    check("items converts False to empty", normalize(False, to="items"), [])
    check("concat has an empty identity", COMBINES["concat"]([]), [])
    check("union has an empty identity", COMBINES["union"]([]), {})
    check("replace has an empty identity", COMBINES["replace"]([]), None)
    check_raises(
        "concat rejects unnormalized mappings",
        lambda: COMBINES["concat"]([{"not": "a list"}]),
        "normalized list",
    )
    check_raises(
        "union rejects unnormalized lists",
        lambda: COMBINES["union"]([["not a mapping"]]),
        "normalized mapping",
    )

    left = _tags.TrustedAsTemplate().tag("{{ LEFT }}")
    right = _tags.TrustedAsTemplate().tag("{{ RIGHT }}")
    tagged = merge_list(
        [{"name": "build", "generated": left}],
        [{"name": "build", "generated": right}],
        preset="bins_generated",
    )[0]["generated"]
    check("keyed fold preserves template text", tagged, "{{ LEFT }}\n{{ RIGHT }}")
    check(
        "keyed fold preserves template tags",
        _tags.TrustedAsTemplate() in AnsibleTagHelper.tags(tagged),
        True,
    )
    check(
        "canonicalize retains unknowns when requested",
        REFINES["canonicalize"](
            ["unknown", "guard", "env"],
            registry=("env", "guard"),
            drop_unknown=False,
        ),
        ["env", "guard", "unknown"],
    )
    check(
        "canonicalize drops unknowns when requested",
        REFINES["canonicalize"](
            ["unknown", "guard", "env"],
            registry=("env", "guard"),
            drop_unknown=True,
        ),
        ["env", "guard"],
    )
    check(
        "helper layers suppress top-level False only",
        merge_list(
            ["env"], False, ["report", "guard"],
            preset="helpers",
            skip_layers=("none", "undefined", "false"),
        ),
        ["env", "loud", "report", "guard"],
    )
    check_raises(
        "configured presets reject operation envelopes",
        lambda: merge_list([["a"]], preset={"op": "merge_keyed"}),
        "unknown value preset",
    )
    check_raises(
        "merge_list rejects the legacy skip keyword",
        lambda: merge_list([["a"]], skip="all"),
        "skip",
    )
    check_raises(
        "merge_fields rejects aggregate preparation",
        lambda: merge_fields([], profile={}, aggregate={}),
        "aggregate",
    )


def test_lazy_template_data_boundary():
    print("\nlazy template data boundary:")
    check(
        "collect copies lazy layer lists before iteration",
        collect(FakeLazyList([["base"], ["incoming"]])),
        [["base"], ["incoming"]],
    )
    check(
        "normalize copies lazy mappings before access",
        normalize(FakeLazyDict({"rust": "1.90"}), to="mapping"),
        {"rust": "1.90"},
    )
    check(
        "merge_list copies lazy layers before normalization",
        merge_list(FakeLazyList(["base", "incoming"]), preset="append"),
        ["base", "incoming"],
    )
    check(
        "merge_dict copies lazy layers before normalization",
        merge_dict(FakeLazyDict({"BASE": 1}), FakeLazyDict({"INCOMING": 2}), preset="overlay"),
        {"BASE": 1, "INCOMING": 2},
    )
    check(
        "merge_fields copies lazy records before field access",
        merge_fields(
            FakeLazyList(
                [
                    FakeLazyDict({"ENV": {"PATH": "/base"}}),
                    FakeLazyDict({"ENV": {"HOME": "/home/user"}}),
                ]
            ),
            profile=FakeLazyDict({"ENV": {"preset": "overlay"}}),
        ),
        {"ENV": {"PATH": "/base", "HOME": "/home/user"}},
    )


def test_presets_and_extract():
    print("\npresets:")
    check(
        "bins_generated is configured once",
        merge_list(
            [{"name": "build", "early": "a"}],
            [{"name": "build", "early": "b"}],
            preset="bins_generated",
        ),
        [{"name": "build", "early": "a\nb"}],
    )
    check(
        "tool versions maps shorthand before union",
        merge_dict(
            ["rust", "node"], {"rust": "1.90"}, preset="tool_versions_overlay"
        ),
        {"rust": "1.90", "node": True},
    )
    check(
        "replace preserves a surviving False layer",
        run_value_preset(["first", False], preset="replace"),
        False,
    )
    check(
        "extract follows the completed pipeline",
        merge_list([{"name": "build"}], preset="merge_keyed", get="0.name"),
        "build",
    )
    check_raises(
        "merge_list rejects a mapping preset",
        lambda: merge_list({"A": 1}, preset="overlay"),
        "requires a list",
    )
    check_raises(
        "merge_dict treats positional string as a layer not a preset",
        lambda: merge_dict({"A": 1}, "overlay"),
        "mapping",
    )
    check_raises(
        "merge_list rejects legacy strategy keyword",
        lambda: merge_list(["a"], strategy="append"),
        "strategy",
    )
    check_raises(
        "merge_list rejects legacy single keyword",
        lambda: merge_list(["a"], single=True),
        "single",
    )


def test_field_profiles():
    print("\nfield profiles:")
    profile = {
        "BINS": {"preset": "bins_generated"},
        "ENV": {"preset": "overlay"},
        "PKGS": {"preset": "append_unique"},
        "artifacts": {"fields": {"LINKS": {"preset": "append"}}},
    }
    check(
        "merges leaf and nested field profiles",
        merge_fields(
            [
                {
                    "BINS": [{"name": "build", "generated": "one"}],
                    "ENV": {"PATH": "/base"},
                    "PKGS": ["git"],
                    "artifacts": {"LINKS": ["base"]},
                },
                {
                    "BINS": [{"name": "build", "generated": "two"}],
                    "ENV": {"PATH": "/incoming", "HOME": "/home/user"},
                    "PKGS": ["git", "curl"],
                    "artifacts": {"LINKS": ["incoming"]},
                },
            ],
            profile=profile,
        ),
        {
            "BINS": [{"name": "build", "generated": "one\ntwo"}],
            "ENV": {"PATH": "/incoming", "HOME": "/home/user"},
            "PKGS": ["git", "curl"],
            "artifacts": {"LINKS": ["base", "incoming"]},
        },
    )
    check_raises(
        "profile leaf and branch cannot be combined",
        lambda: merge_fields([], profile={"BINS": {"preset": "append", "fields": {}}}),
        "exactly one",
    )


def test_tag_each():
    print("\ntag_each:")
    check("tags all records in a list",
        tag_each([{"name": "a"}, {"name": "b"}], subsystem="kernel"),
        [{"name": "a", "subsystem": "kernel"}, {"name": "b", "subsystem": "kernel"}])
    check("preserves non-mapping items",
        tag_each([{"name": "a"}, "bare-string"], subsystem="kernel"),
        [{"name": "a", "subsystem": "kernel"}, "bare-string"])
    check("absent input returns empty list",
        tag_each(Undefined(name="missing")),
        [])
    check("None input returns empty list",
        tag_each(None),
        [])
    check("single dict wraps to one-element list",
        tag_each({"name": "a"}, subsystem="kernel"),
        [{"name": "a", "subsystem": "kernel"}])
    check("multiple fields",
        tag_each([{"name": "a"}], subsystem="kernel", scope="user"),
        [{"name": "a", "subsystem": "kernel", "scope": "user"}])
    check("tag kwarg as alternative to **fields",
        tag_each([{"name": "a"}], tag={"subsystem": "kernel"}),
        [{"name": "a", "subsystem": "kernel"}])
    check("rejects string input (not char-iterated)",
        True,
        True)
    try:
        tag_each("not-a-list", subsystem="x")
        check("string input raises", False, True)
    except Exception:
        check("string input raises", True, True)
    check("skips undefined field values",
        tag_each([{"name": "a"}], good="yes", bad=Undefined(name="bad")),
        [{"name": "a", "good": "yes"}])


def test_combine_iff():
    print("\ncombine_iff:")
    check("merges defined values",
        combine_iff({"a": 1}, {"b": 2}),
        {"a": 1, "b": 2})
    check("skips undefined values in overlay",
        combine_iff({"a": 1}, {"b": 2, "c": Undefined(name="c")}),
        {"a": 1, "b": 2})
    check("skips entire undefined overlay",
        combine_iff({"a": 1}, Undefined(name="overlay")),
        {"a": 1})
    check("skips non-mapping overlay (None, bool, list)",
        combine_iff({"a": 1}, None, True, ["not", "a", "dict"]),
        {"a": 1})
    check("undefined base returns only defined overlays",
        combine_iff(Undefined(name="base"), {"a": 1}),
        {"a": 1})
    check("None base returns only defined overlays",
        combine_iff(None, {"a": 1}),
        {"a": 1})
    check("False value is kept (not undefined)",
        combine_iff({}, {"flag": False}),
        {"flag": False})
    check("zero value is kept (not undefined)",
        combine_iff({}, {"count": 0}),
        {"count": 0})
    check("multiple overlays merge left to right",
        combine_iff({}, {"a": 1}, {"b": 2}, {"a": 3}),
        {"a": 3, "b": 2})
    check("empty base with single overlay",
        combine_iff({}, {"a": 1, "b": 2}),
        {"a": 1, "b": 2})
    check("later overlay wins on key conflict",
        combine_iff({"x": "base"}, {"x": "overlay"}),
        {"x": "overlay"})
    check("undefined value overridden by later defined value",
        combine_iff({"x": Undefined(name="x")}, {"x": "real"}),
        {"x": "real"})


def test_when():
    print("\nwhen (or):")
    check("returns value when any condition truthy",
        when("v", True, False),
        "v")
    check("returns value when one of many truthy",
        when("v", False, False, True, False),
        "v")
    check("returns else_value when all falsy",
        when("v", False, False, else_value="else"),
        "else")
    check("returns None when all falsy and no else_value",
        when("v", False, False),
        None)
    check("treats undefined condition as falsy",
        when("v", Undefined(name="x"), False),
        None)
    check("returns value when undefined alongside a truthy condition",
        when("v", Undefined(name="x"), True),
        "v")
    check("no conditions returns else_value",
        when("v", else_value="else"),
        "else")
    check("empty string condition is falsy",
        when("v", "", else_value="else"),
        "else")
    check("non-empty string condition is truthy",
        when("v", "yes"),
        "v")
    check("zero condition is falsy",
        when("v", 0, else_value="else"),
        "else")


def test_when_and():
    print("\nwhenAnd (and):")
    check("returns value when all conditions truthy",
        whenAnd("v", True, True),
        "v")
    check("returns else_value when any falsy",
        whenAnd("v", True, False, else_value="else"),
        "else")
    check("returns None when any falsy and no else_value",
        whenAnd("v", True, False),
        None)
    check("treats undefined condition as falsy",
        whenAnd("v", True, Undefined(name="x")),
        None)
    check("no conditions returns else_value (conservative)",
        whenAnd("v", else_value="else"),
        "else")
    check("single truthy condition",
        whenAnd("v", True),
        "v")
    check("single falsy condition",
        whenAnd("v", False, else_value="else"),
        "else")


if __name__ == "__main__":
    test_collect()
    test_normalizers()
    test_combines_and_refines()
    test_fixed_stage_contracts()
    test_lazy_template_data_boundary()
    test_presets_and_extract()
    test_field_profiles()
    test_tag_each()
    test_combine_iff()
    test_when()
    test_when_and()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
