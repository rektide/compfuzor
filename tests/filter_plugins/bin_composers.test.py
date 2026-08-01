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


def test_composes_apply_actions():
    result = bin_composers(
        [
            {"name": "apply-kernel.sh"},
            {"name": "apply-sysctl.sh"},
            {"name": "apply-sysfs.sh"},
        ]
    )
    check(
        "composes apply actions",
        result,
        [
            {
                "name": "apply.sh",
                "action": "apply",
                "generated_by": "gen_bins",
                "run_all": ["apply-kernel.sh", "apply-sysctl.sh", "apply-sysfs.sh"],
            },
        ],
    )


def test_build_install_apply_coexist():
    result = bin_composers(
        [
            {"name": "build-kernel.sh"},
            {"name": "install-kernel.sh"},
            {"name": "apply-kernel.sh"},
            {"name": "apply-patches.sh"},
        ]
    )
    names = [c["name"] for c in result]
    check("three action compositors", names, ["build.sh", "install.sh", "apply.sh"])
    apply_c = [c for c in result if c["name"] == "apply.sh"][0]
    check(
        "apply compositor aggregates all apply scripts",
        apply_c["run_all"],
        ["apply-kernel.sh", "apply-patches.sh"],
    )


def test_subsystem_groups_into_subcompositor():
    # Two systemd installers (user scope) + an ungrouped config installer:
    # the systemd pair rolls up under install-systemd-user.sh, which the
    # install-user.sh scope compositor invokes; the config bin stays direct.
    result = bin_composers(
        [
            {"name": "install-socket-daemon-user.sh", "scope": ["user"], "subsystem": "systemd"},
            {"name": "install-service-daemon-user.sh", "scope": ["user"], "subsystem": "systemd"},
            {"name": "install-app-config.sh", "scope": ["user"]},
        ]
    )
    by_name = {c["name"]: c for c in result}
    check(
        "emits systemd subsystem compositor",
        sorted(by_name),
        ["install-systemd-user.sh", "install-user.sh"],
    )
    check(
        "subsystem compositor holds the systemd pair",
        by_name["install-systemd-user.sh"]["run_all"],
        ["install-socket-daemon-user.sh", "install-service-daemon-user.sh"],
    )
    check(
        "subsystem compositor carries user scope",
        by_name["install-systemd-user.sh"]["scope"],
        ["user"],
    )
    check(
        "scope compositor nests subsystem compositor + ungrouped leaf",
        by_name["install-user.sh"]["run_all"],
        ["install-systemd-user.sh", "install-app-config.sh"],
    )


def test_subsystem_single_leaf_stays_direct():
    # A subsystem with only one leaf in an action/scope emits no compositor;
    # the leaf stays a direct child of the scope compositor (no self-wrapper).
    result = bin_composers(
        [
            {"name": "install-rust.sh", "subsystem": "rust"},
            {"name": "install-extra.sh"},
        ]
    )
    names = [c["name"] for c in result]
    check("no single-leaf subsystem compositor", names, ["install.sh"])
    check(
        "lone subsystem leaf stays direct child",
        result[0]["run_all"],
        ["install-rust.sh", "install-extra.sh"],
    )


def test_actions_override():
    # The action set is data-driven: passing actions= extends recognition.
    result = bin_composers(
        [{"name": "status-sysctl.sh"}, {"name": "status-modules.sh"}],
        actions=["status"],
    )
    check(
        "custom action composes",
        [c["name"] for c in result],
        ["status.sh"],
    )


if __name__ == "__main__":
    test_composes_unscoped_actions()
    test_composes_explicit_and_filename_user_scopes()
    test_excludes_generated_compositors()
    test_explicit_scope_classifies_systemd_install()
    test_compose_false_excludes_library_scripts()
    test_composes_apply_actions()
    test_build_install_apply_coexist()
    test_subsystem_groups_into_subcompositor()
    test_subsystem_single_leaf_stays_direct()
    test_actions_override()
