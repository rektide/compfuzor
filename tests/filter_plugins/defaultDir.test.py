#!/usr/bin/env python3

"""Tests for defaultDir.

Covers absolute-path passthrough, relative-path prepend, and the new
undefined/None tolerance (returns the base unchanged). The broken
``raise "string"`` from the old implementation is replaced with AnsibleError;
the missing-base and non-string-arg paths are exercised too.
"""
import importlib.util
import sys

sys.path.insert(0, "library/filter_plugins")

from jinja2 import Undefined  # noqa: E402

from ansible.errors import AnsibleError  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "cf_default_dir", "library/filter_plugins/defaultDir.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

defaultDir = _mod.defaultDir

UNDEF = Undefined()


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}:\n  expected {expected!r}\n  got      {actual!r}")
    print(f"ok: {label}")


def check_raises(label, fn, exc=AnsibleError):
    try:
        fn()
    except exc:
        print(f"ok: {label} (raised {exc.__name__})")
        return
    raise AssertionError(f"{label}: expected {exc.__name__}, nothing raised")


# ---------------------------------------------------------------------------
# Absolute paths pass through
# ---------------------------------------------------------------------------

def test_absolute_slash_passes_through():
    check("absolute /x -> /x", defaultDir("/x", "/base"), "/x")
    check("absolute /deep/path -> /deep/path", defaultDir("/deep/path", "/base"), "/deep/path")


def test_absolute_tilde_passes_through():
    check("~ -> ~", defaultDir("~/x", "/base"), "~/x")


# ---------------------------------------------------------------------------
# Relative paths get prepended
# ---------------------------------------------------------------------------

def test_relative_gets_prepended():
    check("rel x + /base -> /base/x", defaultDir("x", "/base"), "/base/x")
    check("rel deep + base -> base/deep", defaultDir("deep/sub", "files"), "files/deep/sub")


# ---------------------------------------------------------------------------
# Undefined / None tolerance (the new behavior)
# ---------------------------------------------------------------------------

def test_undefined_path_returns_base():
    check("undefined + /base -> /base", defaultDir(UNDEF, "/base"), "/base")
    check("undefined + /srv -> /srv", defaultDir(UNDEF, "/srv/app"), "/srv/app")


def test_none_path_returns_base():
    check("None + /base -> /base", defaultDir(None, "/base"), "/base")


def test_undefined_path_with_falsy_base_returns_falsy():
    """If both path and base are absent, the falsy base propagates."""
    check("undefined + False -> False", defaultDir(UNDEF, False), False)


# ---------------------------------------------------------------------------
# Error conditions (now proper AnsibleError, not the old raise "string")
# ---------------------------------------------------------------------------

def test_relative_with_no_base_raises():
    check_raises(
        "relative + no base raises AnsibleError",
        lambda: defaultDir("rel"),
    )


def test_non_string_base_raises():
    check_raises(
        "non-string base raises",
        lambda: defaultDir("rel", 123),
    )


def test_non_string_path_raises():
    check_raises(
        "non-string path raises (after undefined guard)",
        lambda: defaultDir(123, "/base"),
    )


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
    print(f"\nall {len(tests)} tests passed")
