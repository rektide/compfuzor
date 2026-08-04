#!/usr/bin/env python3

"""Tests for become_calc.

Validates the three resolution branches (COMFUZOR_SHOULD_BECOME → BECOME →
should_become probe), owner/group resolution precedence (arg → scope OWNER/GROUP
→ _cf_user_id/_cf_user_gid), and Omit-on-false-become behavior.

The Ansible @pass_context wrapper is exercised via a fake context that mimics
how Ansible exposes task vars through ``context.get_all()`` (the modern,
non-deprecated path).
"""
import os
import sys

sys.path.insert(0, "library/filter_plugins")

from jinja2 import Undefined

from become import _Omit, resolve_become  # noqa: E402

UNDEF = Undefined()  # real Ansible-compatible undefined sentinel


class FakeContext(dict):
    """Mimic Jinja2 Context for the @pass_context wrapper.

    Supports ``get_all()`` (modern) — the wrapper prefers it over the
    deprecated ``context['vars']`` magic.
    """

    def get(self, key, default=None):
        return dict.get(self, key, default)

    def get_all(self):
        return dict(self)


def fake_scope(**overrides):
    """A scope where all flags default to *absent* (key not present).

    Use ``key=UNDEF`` to simulate 'present but undefined' (a Jinja template
    that resolved to an undefined var), and ``key=None`` or ``key=''`` to
    simulate 'present but falsy' (matching ``default(_, true)`` semantics).
    Most tests want pure absence, so we don't put the key in at all unless
    overridden.
    """
    base = {
        "_cf_user_id": 1000,
        "_cf_user_gid": 1000,
    }
    for k, v in overrides.items():
        base[k] = v
    return base


def fake_should_become(result):
    """Build a should_become stub returning ``result`` and recording its args."""

    calls = []

    def fn(path, owner, user_cur, group, group_cur):
        calls.append((path, owner, user_cur, group, group_cur))
        return result

    fn.calls = calls
    return fn


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}:\n  expected {expected!r}\n  got      {actual!r}")
    print(f"ok: {label}")


# ---------------------------------------------------------------------------
# Branch 1: COMFUZOR_SHOULD_BECOME wins
# ---------------------------------------------------------------------------

def test_comfuzor_should_become_true_short_circuits():
    fn = fake_should_become(False)
    out = resolve_become(
        fake_scope(COMFUZOR_SHOULD_BECOME=True),
        "/some/path",
        should_become_fn=fn,
    )
    check("COMFUZOR_SHOULD_BECOME=True -> become True", out["become"], True)
    check("should_become NOT probed", fn.calls, [])
    check("owner falls back to _cf_user_id", out["owner"], 1000)
    check("group falls back to _cf_user_gid", out["group"], 1000)


def test_comfuzor_should_become_false_short_circuits():
    fn = fake_should_become(True)  # would be True if we asked
    out = resolve_become(
        fake_scope(COMFUZOR_SHOULD_BECOME=False),
        "/some/path",
        should_become_fn=fn,
    )
    check("COMFUZOR_SHOULD_BECOME=False -> become False", out["become"], False)
    check("should_become NOT probed", fn.calls, [])
    check("owner is Omit when not becoming", out["owner"], _Omit)
    check("group is Omit when not becoming", out["group"], _Omit)


# ---------------------------------------------------------------------------
# Branch 2: BECOME wins when COMFUZOR_SHOULD_BECOME absent
# ---------------------------------------------------------------------------

def test_become_var_wins_when_comfuzor_unset():
    fn = fake_should_become(False)
    out = resolve_become(
        fake_scope(BECOME=True),
        "/some/path",
        should_become_fn=fn,
    )
    check("BECOME=True (COMFUZOR unset) -> become True", out["become"], True)
    check("should_become NOT probed", fn.calls, [])


def test_become_false_does_not_probe_filesystem():
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(BECOME=False),
        "/some/path",
        should_become_fn=fn,
    )
    check("BECOME=False -> become False", out["become"], False)
    check("should_become NOT probed", fn.calls, [])


# ---------------------------------------------------------------------------
# Branch 3: should_become probe runs when neither override is set
# ---------------------------------------------------------------------------

def test_should_become_probe_runs_when_no_override():
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER="alice", GROUP="staff"),
        "/etc/secret",
        should_become_fn=fn,
    )
    check("probe-driven become True", out["become"], True)
    check(
        "probe received (path, owner, user_cur, group, group_cur)",
        fn.calls[0],
        ("/etc/secret", "alice", 1000, "staff", 1000),
    )
    check("owner preserved when becoming", out["owner"], "alice")
    check("group preserved when becoming", out["group"], "staff")


def test_probe_false_yields_omit_owner_group():
    fn = fake_should_become(False)
    out = resolve_become(
        fake_scope(OWNER="alice"),
        "/tmp/mine",
        should_become_fn=fn,
    )
    check("probe False -> become False", out["become"], False)
    check("owner Omit when probe says no become", out["owner"], _Omit)
    check("group Omit when probe says no become", out["group"], _Omit)


# ---------------------------------------------------------------------------
# Owner/group arg overrides scope OWNER/GROUP
# ---------------------------------------------------------------------------

def test_filter_arg_overrides_scope_owner():
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER="scope-owner"),
        "/x",
        owner="arg-owner",
        should_become_fn=fn,
    )
    check("arg owner beats scope owner", fn.calls[0][1], "arg-owner")
    check("resolved owner is arg-owner", out["owner"], "arg-owner")


def test_filter_group_arg_overrides():
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(GROUP="scope-group"),
        "/x",
        group="arg-group",
        should_become_fn=fn,
    )
    check("arg group beats scope group", fn.calls[0][3], "arg-group")
    check("resolved group is arg-group", out["group"], "arg-group")


# ---------------------------------------------------------------------------
# Absent vs undefined vs None vs empty-string (the falsy matrix)
# ---------------------------------------------------------------------------

def test_absent_key_falls_through():
    """A key missing from scope entirely falls through to the next branch."""
    fn = fake_should_become(True)
    out = resolve_become(fake_scope(), "/x", should_become_fn=fn)
    check("no overrides -> probe runs", fn.calls, [("/x", None, 1000, None, 1000)])
    check("probe True -> become True", out["become"], True)


def test_undefined_value_falls_through():
    """A scope value of Ansible-undefined falls through (key present, value undefined)."""
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(COMFUZOR_SHOULD_BECOME=UNDEF),
        "/x",
        should_become_fn=fn,
    )
    check("undefined COMFUZOR_SHOULD_BECOME -> probe runs", fn.calls, [("/x", None, 1000, None, 1000)])


def test_become_none_is_present_and_falsy():
    """BECOME=None is *present* (defined as None), coerced to bool -> False.

    This matches Ansible's ``BECOME|default(...)`` without the ``true`` flag:
    None does not trigger default fallback, so bool(None)=False wins.
    """
    fn = fake_should_become(True)  # would be True if we probed
    out = resolve_become(
        fake_scope(BECOME=None),
        "/x",
        should_become_fn=fn,
    )
    check("BECOME=None -> become False (not fall-through)", out["become"], False)
    check("probe did NOT run", fn.calls, [])


def test_owner_none_falls_through_to_cf_user_id():
    """OWNER=None: the probe sees None (should_become.good() handles it),
    but the final owner_val falls back to _cf_user_id. Matches the original
    ``owner|default(_cf_user_id, true)`` final-stage fallback."""
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER=None),
        "/x",
        should_become_fn=fn,
    )
    check("OWNER=None -> probe sees None (handled by should_become.good)", fn.calls[0][1], None)
    check("final owner_val falls back to cf_user_id", out["owner"], 1000)


def test_owner_empty_string_falls_through():
    """OWNER='': same as None — probe sees None, final owner_val is cf_user_id."""
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER=""),
        "/x",
        should_become_fn=fn,
    )
    check("OWNER='' -> probe sees None", fn.calls[0][1], None)
    check("final owner_val is cf_user_id", out["owner"], 1000)


def test_owner_undefined_falls_through():
    """OWNER=<undefined>: same — probe sees None, final owner_val is cf_user_id."""
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER=UNDEF),
        "/x",
        should_become_fn=fn,
    )
    check("OWNER=undefined -> probe sees None", fn.calls[0][1], None)
    check("final owner_val is cf_user_id", out["owner"], 1000)


def test_filter_arg_none_defers_to_scope():
    """owner=None (Python default) means 'use scope OWNER', not 'force None'."""
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER="scope-owner"),
        "/x",
        owner=None,
        should_become_fn=fn,
    )
    check("None arg defers to scope OWNER", fn.calls[0][1], "scope-owner")
    check("resolved owner is scope-owner", out["owner"], "scope-owner")


def test_filter_arg_undefined_defers_to_scope():
    """owner=<undefined> (Jinja passed an undefined var) defers to scope."""
    fn = fake_should_become(True)
    out = resolve_become(
        fake_scope(OWNER="scope-owner"),
        "/x",
        owner=UNDEF,
        should_become_fn=fn,
    )
    check("undefined arg defers to scope OWNER", fn.calls[0][1], "scope-owner")


# ---------------------------------------------------------------------------
# @pass_context integration: vars extracted from context the same way as vars.py
# ---------------------------------------------------------------------------

def test_pass_context_extracts_vars_dict():
    """The @pass_context wrapper reads scope via ``context.get_all()``
    (the modern, non-deprecated path). The scope is the context's own
    variable storage — play + role + task vars all land there."""
    from become import FilterModule

    fm = FilterModule()
    scope = fake_scope(COMFUZOR_SHOULD_BECOME=True)

    captured = {}

    def spy(scope, path, owner=None, group=None, should_become_fn=None):
        captured["scope"] = scope
        captured["path"] = path
        captured["owner"] = owner
        captured["group"] = group
        return {"become": True, "owner": owner, "group": group}

    import become as become_mod

    orig = become_mod.resolve_become
    become_mod.resolve_become = spy
    try:
        ctx = FakeContext(scope)  # scope IS the context's vars now
        out = fm.become_calc(ctx, "/from/context", owner="ctx-owner")
    finally:
        become_mod.resolve_become = orig

    check("wrapper forwarded scope dict", captured["scope"], scope)
    check("wrapper forwarded path", captured["path"], "/from/context")
    check("wrapper forwarded owner kwarg", captured["owner"], "ctx-owner")
    check("wrapper forwarded group default None", captured["group"], None)
    check("spy output passed through", out, {"become": True, "owner": "ctx-owner", "group": None})


def test_pass_context_handles_empty_context():
    """If context has no relevant keys, behave as a minimal scope (probe runs)."""
    from become import FilterModule

    fm = FilterModule()
    captured = {}

    def spy(scope, path, owner=None, group=None, should_become_fn=None):
        captured["scope"] = scope
        return {"become": False, "owner": None, "group": None}

    import become as become_mod

    orig = become_mod.resolve_become
    become_mod.resolve_become = spy
    try:
        ctx = FakeContext()  # empty context
        fm.become_calc(ctx, "/x")
    finally:
        become_mod.resolve_become = orig

    check("empty context -> empty dict scope", captured["scope"], {})


if __name__ == "__main__":
    tests = [
        test_comfuzor_should_become_true_short_circuits,
        test_comfuzor_should_become_false_short_circuits,
        test_become_var_wins_when_comfuzor_unset,
        test_become_false_does_not_probe_filesystem,
        test_should_become_probe_runs_when_no_override,
        test_probe_false_yields_omit_owner_group,
        test_filter_arg_overrides_scope_owner,
        test_filter_group_arg_overrides,
        test_absent_key_falls_through,
        test_undefined_value_falls_through,
        test_become_none_is_present_and_falsy,
        test_owner_none_falls_through_to_cf_user_id,
        test_owner_empty_string_falls_through,
        test_owner_undefined_falls_through,
        test_filter_arg_none_defers_to_scope,
        test_filter_arg_undefined_defers_to_scope,
        test_pass_context_extracts_vars_dict,
        test_pass_context_handles_empty_context,
    ]
    for t in tests:
        t()
    print(f"\nall {len(tests)} tests passed")
