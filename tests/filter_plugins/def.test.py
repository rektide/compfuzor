#!/usr/bin/env python3

"""Tests for the def / truthy / deflengthy filters.

Covers the variadic ``def`` semantics (first non-undefined arg, else None)
and the existing binary ``truthy`` / ``deflengthy`` behavior. Uses a real
Ansible-undefined sentinel so the wrapped_test_undefined check is exercised
the same way it is under live Ansible.
"""
import importlib.util
import sys

sys.path.insert(0, "library/filter_plugins")

# ``def`` is a Python keyword, so we can't ``from def import ...``; load the
# module by path instead.
_spec = importlib.util.spec_from_file_location("cf_def", "library/filter_plugins/def.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

lengthy = _mod.lengthy
truthy = _mod.truthy
un_undefine = _mod.un_undefine

from jinja2 import Undefined  # noqa: E402

UNDEF = Undefined()


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}:\n  expected {expected!r}\n  got      {actual!r}")
    print(f"ok: {label}")


# ---------------------------------------------------------------------------
# def — variadic semantics
# ---------------------------------------------------------------------------

def test_def_no_args_returns_none():
    check("def() with no args -> None", un_undefine(), None)


def test_def_single_defined_returns_it():
    check("def('x') -> 'x'", un_undefine("x"), "x")
    check("def(0) -> 0 (falsy-but-defined passes through)", un_undefine(0), 0)
    check("def(None) -> None (None is defined, not undefined)", un_undefine(None), None)
    check("def('') -> '' (empty string is defined)", un_undefine(""), "")
    check("def(False) -> False (False is defined)", un_undefine(False), False)


def test_def_single_undefined_returns_none():
    check("def(UNDEF) -> None", un_undefine(UNDEF), None)


def test_def_two_args_first_defined_wins():
    check("def('x', 'y') -> 'x'", un_undefine("x", "y"), "x")
    check("def(0, 'y') -> 0 (falsy defined wins)", un_undefine(0, "y"), 0)
    check("def(None, 'y') -> None (None is defined, wins over y)", un_undefine(None, "y"), None)


def test_def_two_args_first_undefined_second_defined():
    check("def(UNDEF, 'y') -> 'y'", un_undefine(UNDEF, "y"), "y")


def test_def_two_args_both_undefined_returns_none():
    """Latent-bug fix: old impl returned the second arg's undefined marker;
    variadic impl returns None. Audited all 17 existing |def sites — none
    rely on the marker leaking through."""
    check("def(UNDEF, UNDEF) -> None (not the marker)", un_undefine(UNDEF, UNDEF), None)


def test_def_three_args_walks_left_to_right():
    check("def('a', 'b', 'c') -> 'a'", un_undefine("a", "b", "c"), "a")
    check("def(UNDEF, 'b', 'c') -> 'b'", un_undefine(UNDEF, "b", "c"), "b")
    check("def(UNDEF, UNDEF, 'c') -> 'c'", un_undefine(UNDEF, UNDEF, "c"), "c")
    check("def(UNDEF, UNDEF, UNDEF) -> None", un_undefine(UNDEF, UNDEF, UNDEF), None)


def test_def_literal_final_fallback():
    """The intended P5/P9 idiom: var -> register -> literal string."""
    check("def(UNDEF, UNDEF, 'default') -> 'default'", un_undefine(UNDEF, UNDEF, "default"), "default")
    check(
        "def(base.stdout, HOMEDIR+'/x') with base.stdout UNDEF -> literal",
        un_undefine(UNDEF, "/home/user/x"),
        "/home/user/x",
    )


def test_def_preserves_falsy_defined_values():
    """Important for P5: a real falsy value (0, '', False) must not be
    skipped — only undefined markers are."""
    check("def(0, 'fallback') -> 0", un_undefine(0, "fallback"), 0)
    check("def('', 'fallback') -> ''", un_undefine("", "fallback"), "")
    check("def(False, 'fallback') -> False", un_undefine(False, "fallback"), False)
    check("def(0, '', False) -> 0 (first defined, even if falsy)", un_undefine(0, "", False), 0)


# ---------------------------------------------------------------------------
# truthy — unchanged binary behavior, just sanity-check
# ---------------------------------------------------------------------------

def test_truthy_undefined_returns_false():
    check("truthy(UNDEF) -> False", truthy(UNDEF), False)


def test_truthy_undefined_with_fallback():
    check("truthy(UNDEF, True) -> True", truthy(UNDEF, True), True)
    check("truthy(UNDEF, False) -> False", truthy(UNDEF, False), False)


def test_truthy_defined_coerces():
    check("truthy('x') -> True", truthy("x"), True)
    check("truthy('') -> False (empty string)", truthy(""), False)
    check("truthy(0) -> False", truthy(0), False)
    check("truthy(1) -> True", truthy(1), True)
    check("truthy(None) -> False", truthy(None), False)


# ---------------------------------------------------------------------------
# deflengthy — unchanged binary behavior, just sanity-check
# ---------------------------------------------------------------------------

def test_deflengthy_undefined_returns_false():
    check("deflengthy(UNDEF) -> False", lengthy(UNDEF), False)


def test_deflengthy_undefined_with_fallback_list():
    check("deflengthy(UNDEF, [1]) -> True", lengthy(UNDEF, [1]), True)


def test_deflengthy_non_empty_list():
    check("deflengthy([1, 2]) -> True", lengthy([1, 2]), True)


def test_deflengthy_empty_list():
    check("deflengthy([]) -> False", lengthy([]), False)


def test_deflengthy_non_empty_string_is_lengthy():
    # Note: deflengthy uses len() which works on strings; a non-empty string
    # has length > 0 and returns True. This matches the existing documented
    # behavior — the filter is "list-like with len > 0", not "is a list".
    check("deflengthy('string') -> True (len > 0)", lengthy("string"), True)


def test_deflengthy_none():
    check("deflengthy(None) -> False (None has no len)", lengthy(None), False)


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
    print(f"\nall {len(tests)} tests passed")
