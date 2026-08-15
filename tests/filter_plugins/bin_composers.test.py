#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from bin_composers import bin_composers, partition_bin_states  # noqa: E402


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def check_raises(label, operation, expected):
    try:
        operation()
    except Exception as error:
        if expected not in str(error):
            raise AssertionError(
                f"{label}: expected error containing {expected!r}, got {error!r}"
            ) from error
        print(f"ok: {label}")
        return
    raise AssertionError(f"{label}: expected an exception")


def test_composes_unscoped_actions():
    result = bin_composers(
        [
            {"name": "build.sh"},
            {"name": "build-app.sh"},
            {"name": "install-app.sh"},
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
                "run_all": ["build-app.sh"],
                "base_helpers": ["env", "setopts", "loud"],
            },
            {
                "name": "install.sh",
                "action": "install",
                "generated_by": "gen_bins",
                "run_all": ["install-app.sh"],
                "base_helpers": ["env", "setopts", "loud"],
            },
        ],
    )


def test_composes_explicit_and_filename_user_scopes():
    result = bin_composers(
        [
            {"name": "install-user.sh"},
            {"name": "install-shell.sh", "scope": ["user", "shell"]},
            {"name": "install-shell-extra.sh", "scope": "shell"},
            {"name": "install-bash-user.sh"},
            {"name": "install-user-zimfw.sh"},
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
                "run_all": [
                    "install-shell.sh",
                    "install-bash-user.sh",
                    "install-user-zimfw.sh",
                ],
                "scope": ["user"],
                "base_helpers": ["env", "setopts", "loud"],
            },
            {
                "name": "install-shell.sh",
                "action": "install",
                "generated_by": "gen_bins",
                "run_all": ["install-shell-extra.sh"],
                "scope": ["shell"],
                "base_helpers": ["env", "setopts", "loud"],
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


def test_absent_bins_are_partitioned_and_not_composed():
    bins = [
        {"name": "build-nodejs.sh", "state": "absent"},
        {"name": "install-live.sh"},
    ]
    check(
        "partitions absent tombstones",
        partition_bin_states(bins),
        {
            "present": [{"name": "install-live.sh"}],
            "absent": [{"name": "build-nodejs.sh", "state": "absent"}],
        },
    )
    check(
        "absent build leaf creates no compositor",
        [item["name"] for item in bin_composers(bins)],
        ["install.sh"],
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
            {"name": "apply-cache.sh"},
            {"name": "apply-network.sh"},
            {"name": "apply-storage.sh"},
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
                "run_all": ["apply-cache.sh", "apply-network.sh", "apply-storage.sh"],
                "base_helpers": ["env", "setopts", "loud"],
            },
        ],
    )


def test_build_install_apply_coexist():
    result = bin_composers(
        [
            {"name": "build-project.sh"},
            {"name": "install-project.sh"},
            {"name": "apply-project.sh"},
            {"name": "apply-patches.sh"},
        ]
    )
    names = [c["name"] for c in result]
    check("three action compositors", names, ["build.sh", "install.sh", "apply.sh"])
    apply_c = [c for c in result if c["name"] == "apply.sh"][0]
    check(
        "apply compositor aggregates all apply scripts",
        apply_c["run_all"],
        ["apply-project.sh", "apply-patches.sh"],
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


def test_kernel_leaf_names_create_pure_subsystem_compositors():
    leaves = [
        {"name": "build-kernel-modprobe.sh", "subsystem": "kernel"},
        {"name": "install-kernel-modprobe.sh", "subsystem": "kernel"},
        {"name": "apply-kernel-modprobe.sh", "subsystem": "kernel"},
        {
            "name": "install-kernel-cmdline.sh",
            "subsystem": "kernel",
            "compose": False,
        },
        {"name": "build-kernel-sysctl.sh", "subsystem": "kernel"},
        {"name": "install-kernel-sysctl.sh", "subsystem": "kernel"},
        {"name": "apply-kernel-sysctl.sh", "subsystem": "kernel"},
        {"name": "build-kernel-sysfs.sh", "subsystem": "kernel"},
        {"name": "install-kernel-sysfs.sh", "subsystem": "kernel"},
        {"name": "apply-kernel-sysfs.sh", "subsystem": "kernel"},
        {"name": "install-kernel-params.sh", "subsystem": "kernel"},
        {"name": "install-kernel-bls.sh", "subsystem": "kernel"},
    ]

    result = bin_composers(leaves)
    by_name = {compositor["name"]: compositor for compositor in result}
    check(
        "kernel hierarchy emits pure subsystem and scope compositors",
        list(by_name),
        [
            "build-kernel.sh",
            "install-kernel.sh",
            "apply-kernel.sh",
            "build.sh",
            "install.sh",
            "apply.sh",
        ],
    )
    check(
        "kernel build compositor owns qualified leaves",
        by_name["build-kernel.sh"]["run_all"],
        [
            "build-kernel-modprobe.sh",
            "build-kernel-sysctl.sh",
            "build-kernel-sysfs.sh",
        ],
    )
    check(
        "kernel install compositor owns qualified leaves in contribution order",
        by_name["install-kernel.sh"]["run_all"],
        [
            "install-kernel-modprobe.sh",
            "install-kernel-sysctl.sh",
            "install-kernel-sysfs.sh",
            "install-kernel-params.sh",
            "install-kernel-bls.sh",
        ],
    )
    check(
        "kernel apply compositor owns qualified leaves",
        by_name["apply-kernel.sh"]["run_all"],
        [
            "apply-kernel-modprobe.sh",
            "apply-kernel-sysctl.sh",
            "apply-kernel-sysfs.sh",
        ],
    )
    check(
        "scope compositors call only kernel compositors",
        [
            by_name["build.sh"]["run_all"],
            by_name["install.sh"]["run_all"],
            by_name["apply.sh"]["run_all"],
        ],
        [["build-kernel.sh"], ["install-kernel.sh"], ["apply-kernel.sh"]],
    )
    check(
        "reserved compositor names are not authored leaves",
        any(leaf["name"] in by_name for leaf in leaves),
        False,
    )


def test_subsystem_single_leaf_keeps_compositor():
    result = bin_composers(
        [
            {"name": "install-rust-toolchain.sh", "subsystem": "rust"},
            {"name": "install-extra.sh"},
        ]
    )
    by_name = {compositor["name"]: compositor for compositor in result}
    check(
        "single-leaf subsystem keeps compositor",
        by_name["install-rust.sh"]["run_all"],
        ["install-rust-toolchain.sh"],
    )
    check(
        "scope references single-leaf subsystem compositor",
        by_name["install.sh"]["run_all"],
        ["install-rust.sh", "install-extra.sh"],
    )


def test_rejects_reserved_subsystem_compositor_name():
    check_raises(
        "rejects reserved subsystem compositor name",
        lambda: bin_composers(
            [{"name": "build-kernel.sh", "subsystem": "kernel"}]
        ),
        "reserved subsystem compositor name",
    )
    check_raises(
        "rejects untagged reserved compositor collision",
        lambda: bin_composers(
            [
                {"name": "build-kernel.sh"},
                {"name": "build-kernel-sysctl.sh", "subsystem": "kernel"},
            ]
        ),
        "reserved subsystem compositor name",
    )
    check_raises(
        "rejects non-composing reserved compositor collision",
        lambda: bin_composers(
            [
                {"name": "build-kernel.sh", "compose": False},
                {"name": "build-kernel-sysctl.sh", "subsystem": "kernel"},
            ]
        ),
        "reserved subsystem compositor name",
    )
    check_raises(
        "rejects reserved compositor collision across scopes",
        lambda: bin_composers(
            [
                {"name": "install-systemd-user.sh", "compose": False},
                {
                    "name": "install-service-app-user.sh",
                    "scope": "user",
                    "subsystem": "systemd",
                },
            ]
        ),
        "reserved subsystem compositor name",
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


def test_disarm_metadata_does_not_affect_grouping_or_compositors():
    result = bin_composers(
        [
            {
                "name": "build-go-app.sh",
                "subsystem": "go",
                "origin_subsystems": ["go", "generator"],
                "bypass_scopes": ["go"],
            }
        ]
    )
    check(
        "provenance does not create extra groups",
        [item["name"] for item in result],
        ["build-go.sh", "build.sh"],
    )
    for item in result:
        check(
            f"{item['name']} does not aggregate child disarm metadata",
            any(field in item for field in ("origin_subsystems", "bypass_scopes", "bypass")),
            False,
        )


if __name__ == "__main__":
    test_composes_unscoped_actions()
    test_composes_explicit_and_filename_user_scopes()
    test_excludes_generated_compositors()
    test_absent_bins_are_partitioned_and_not_composed()
    test_explicit_scope_classifies_systemd_install()
    test_compose_false_excludes_library_scripts()
    test_composes_apply_actions()
    test_build_install_apply_coexist()
    test_subsystem_groups_into_subcompositor()
    test_kernel_leaf_names_create_pure_subsystem_compositors()
    test_subsystem_single_leaf_keeps_compositor()
    test_rejects_reserved_subsystem_compositor_name()
    test_actions_override()
    test_disarm_metadata_does_not_affect_grouping_or_compositors()
