#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from bin_composers import bin_composers  # noqa: E402


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def test_composes_unscoped_actions():
    result = bin_composers(
        [
            {"name": "build.sh"},
            {"name": "build-kernel.sh"},
            {"name": "install-kernel.sh"},
        ]
    )
    check(
        "composes unscoped actions",
        result,
        [
            {
                "name": "build.sh",
                "action": "build",
                "generated_by": "gen_bins",
                "run_all": ["build-kernel.sh"],
            },
            {
                "name": "install.sh",
                "action": "install",
                "generated_by": "gen_bins",
                "run_all": ["install-kernel.sh"],
                "kernel": True,
            },
        ],
    )


def test_composes_explicit_and_filename_user_scopes():
    result = bin_composers(
        [
            {"name": "install-user.sh"},
            {"name": "install-shell.sh", "scope": ["user", "shell"]},
            {"name": "install-shell-extra.sh", "scope": "shell"},
            {"name": "install-bash.user.sh", "scope": "user"},
        ]
    )
    check(
        "arrayifies and contains scopes",
        result,
        [
            {
                "name": "install-user.sh",
                "action": "install",
                "generated_by": "gen_bins",
                "run_all": ["install-shell.sh", "install-bash.user.sh"],
                "scope": ["user"],
            },
            {
                "name": "install-shell.sh",
                "action": "install",
                "generated_by": "gen_bins",
                "run_all": ["install-shell-extra.sh"],
                "scope": ["shell"],
            },
        ],
    )


def test_excludes_generated_compositors():
    result = bin_composers(
        [
            {"name": "build.sh"},
            {"name": "build-all.sh", "generated_by": "gen_bins"},
        ]
    )
    check(
        "excludes generated compositors",
        result,
        [],
    )


def test_explicit_scope_classifies_systemd_install():
    # Mirrors what vars_systemd_unit.tasks emits: install-service-user.sh with
    # an explicit user scope (filename alone would not match install-user/.user).
    # Note: subsystem-generated bins carry `generated` content but NO
    # `generated_by: gen_bins` marker (that marks gen_bins' own compositor output).
    result = bin_composers(
        [
            {"name": "install-user.sh"},
            {
                "name": "install-service-user.sh",
                "scope": ["user"],
                "generated": 'echo hi',
            },
        ]
    )
    user = [c for c in result if c["name"] == "install-user.sh"]
    check("emits install-user compositor", len(user), 1)
    check(
        "systemd user-scope install joins user compositor",
        user[0]["run_all"],
        ["install-service-user.sh"],
    )
    check("user compositor carries scope", user[0].get("scope"), ["user"])


def test_compose_false_excludes_library_scripts():
    # install-unit.sh is a library sourced by per-type scripts, not an action.
    result = bin_composers(
        [
            {"name": "install-user.sh"},
            {
                "name": "install-unit.sh",
                "src": "../systemd/install-unit.sh",
                "compose": False,
            },
        ]
    )
    names = [c["name"] for c in result]
    check("no unscoped install compositor", "install.sh" not in names, True)
    check(
        "install-unit.sh excluded from user compositor",
        "install-user.sh" not in names,
        True,
    )


if __name__ == "__main__":
    test_composes_unscoped_actions()
    test_composes_explicit_and_filename_user_scopes()
    test_excludes_generated_compositors()
    test_explicit_scope_classifies_systemd_install()
    test_compose_false_excludes_library_scripts()
