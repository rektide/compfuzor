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

from merge_pipeline import (
    COMBINES,
    REFINES,
    collect,
    merge_dict,
    merge_fields,
    merge_list,
    normalize,
    run_value_preset,
)

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


if __name__ == "__main__":
    test_collect()
    test_normalizers()
    test_combines_and_refines()
    test_fixed_stage_contracts()
    test_lazy_template_data_boundary()
    test_presets_and_extract()
    test_field_profiles()
    print("\n{} passed, {} failed".format(passed, failed))
    sys.exit(1 if failed else 0)
