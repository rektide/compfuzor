#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from config_compile import compile_config, publish_config


def check(label, actual, expected):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def check_raises(label, callback, expected):
    try:
        callback()
    except AnsibleFilterError as error:
        if expected not in str(error):
            raise AssertionError(f"{label}: unexpected error: {error}") from error
    else:
        raise AssertionError(f"{label}: did not raise")
    print(f"ok: {label}")


def fixture():
    dropins = {
        "app-core": {
            "root": "/srv/app/etc",
            "path": "core.d",
            "include": "*.json",
            "disabled_suffix": ".disabled",
            "files": [{"name": "10-core.json", "json": {"core": True}}],
        },
        "app-mcp": {
            "root": "/srv/app/etc",
            "path": "mcp",
            "include": "*.json",
            "disabled_suffix": ".disabled",
        },
        "policy": {
            "root": "/srv/app/etc",
            "path": "policy.d",
            "include": "*.conf",
        },
    }
    configs = {
        "app": {
            "root": "/srv/app/etc",
            "assemblies": {
                "mcp": {
                    "output": "generated/mcp.json",
                    "processor": "json-deep-merge",
                    "inputs": [{"dropins": "app-mcp"}],
                },
                "main": {
                    "output": "app.json",
                    "processor": "json-deep-merge",
                    "inputs": [
                        {"file": "base.json"},
                        {"dropins": "app-core"},
                        {"artifact": "mcp"},
                    ],
                },
            },
        },
        "shell": {
            "root": "/srv/app/etc",
            "assemblies": {
                "main": {
                    "output": "shellrc",
                    "processor": "block-in-file",
                    "block": {"after": "HEADER", "namespace": "managed/shell"},
                    "inputs": [{"dropins": "policy", "block": {"after": "LOCAL"}}],
                }
            },
        },
        "policy": {
            "root": "/srv/app/etc",
            "assemblies": {
                "main": {
                    "output": "policy.conf",
                    "processor": "concat",
                    "validate": "test -s \"$CONFIG_CANDIDATE\"",
                    "inputs": [{"dropins": "policy"}],
                }
            },
        },
    }
    return dropins, configs


def test_compile():
    dropins, configs = fixture()
    plan = compile_config(dropins, configs)

    check(
        "drop-in directories",
        plan["dirs"],
        [
            "/srv/app/etc/core.d",
            "/srv/app/etc/mcp",
            "/srv/app/etc/policy.d",
            "/srv/app/etc/generated",
            "/srv/app/etc",
        ],
    )
    check(
        "drop-in file destination",
        plan["files"][0]["dest"],
        "/srv/app/etc/core.d/10-core.json",
    )
    check("stable assembly order", plan["spec"]["configs"]["app"]["order"], ["mcp", "main"])
    check(
        "artifact resolves to output",
        plan["spec"]["configs"]["app"]["assemblies"]["main"]["inputs"][2],
        {"artifact": "mcp", "path": "/srv/app/etc/generated/mcp.json"},
    )
    check(
        "independent config output",
        plan["spec"]["configs"]["policy"]["assemblies"]["main"]["output"],
        "/srv/app/etc/policy.conf",
    )
    check(
        "candidate validation",
        plan["spec"]["configs"]["policy"]["assemblies"]["main"]["validate"],
        'test -s "$CONFIG_CANDIDATE"',
    )

    names = [item["name"] if "name" in item else item["dest"] for item in plan["bins"]]
    check(
        "generated command names",
        names,
        [
            "config.sh",
            "config-toggle.sh",
            "config-processor.sh",
            "processors/block-in-file",
            "processors/concat",
            "processors/json-deep-merge",
            "internal/config/app/mcp",
            "internal/config/app/main",
            "config-app.sh",
            "disable-app.sh",
            "enable-app.sh",
            "status-config-app.sh",
            "internal/config/shell/main",
            "config-shell.sh",
            "status-config-shell.sh",
            "internal/config/policy/main",
            "config-policy.sh",
            "status-config-policy.sh",
        ],
    )
    check("status names", plan["statuses"], ["status-config-app.sh", "status-config-shell.sh", "status-config-policy.sh"])
    check(
        "leaf shares processor command",
        next(item for item in plan["bins"] if item.get("dest") == "internal/config/app/main")["link"],
        "processors/json-deep-merge",
    )
    check(
        "block input inheritance",
        plan["spec"]["configs"]["shell"]["assemblies"]["main"]["inputs"][0]["block"],
        {"after": "LOCAL", "namespace": "managed/shell"},
    )

    subsystems = {
        "config": {"existing": "preserved"},
        "other": {"spec": "{{ undefined_until_other_subsystem_runs }}"},
    }
    published = publish_config(subsystems, plan)
    check("unrelated subsystem preserved", published["other"], subsystems["other"])
    check("existing config state preserved", published["config"]["existing"], "preserved")
    check("normalized spec published", published["config"]["spec"], plan["spec"])
    check("config dirs contributed", published["config"]["contrib"]["DIRS"], plan["dirs"])
    check(
        "config spec file contributed",
        published["config"]["contrib"]["ETC_FILES"][-1],
        {"name": "config.spec.json", "json": plan["spec"]},
    )
    check("config bins contributed", published["config"]["contrib"]["BINS"], plan["bins"])
    check("config statuses contributed", published["config"]["contrib"]["STATUSES"], plan["statuses"])
    check("config packages contributed", published["config"]["contrib"]["PKGS"], ["jq"])


def test_validation():
    dropins, configs = fixture()
    configs["app"]["assemblies"]["mcp"]["inputs"] = [{"artifact": "missing"}]
    check_raises(
        "unknown artifact",
        lambda: compile_config(dropins, configs),
        "unknown artifact 'missing'",
    )

    dropins, configs = fixture()
    configs["app"]["assemblies"]["mcp"]["inputs"] = [{"artifact": "main"}]
    check_raises(
        "assembly cycle",
        lambda: compile_config(dropins, configs),
        "cycle",
    )

    dropins, configs = fixture()
    configs["app"]["assemblies"]["main"]["inputs"][1] = {"dropins": "missing"}
    check_raises(
        "unknown drop-in",
        lambda: compile_config(dropins, configs),
        "unknown drop-in 'missing'",
    )

    dropins, configs = fixture()
    dropins["app-core"]["path"] = "~/core.d"
    check_raises(
        "unexpanded tilde path",
        lambda: compile_config(dropins, configs),
        "must not use an unexpanded '~' path",
    )

    dropins, configs = fixture()
    configs["app"]["root"] = "~/.config/app"
    check_raises(
        "unexpanded tilde root",
        lambda: compile_config(dropins, configs),
        "root must not use an unexpanded '~' path",
    )

    dropins, configs = fixture()
    configs["shell"]["assemblies"]["main"]["inputs"][0]["block"] = {"before": "LOCAL"}
    check_raises(
        "placement conflict after inheritance",
        lambda: compile_config(dropins, configs),
        "conflicting placement settings",
    )

    dropins, configs = fixture()
    configs["shell"]["assemblies"]["main"]["inputs"][0]["block"] = {"namespace": "stolen"}
    check_raises(
        "input namespace rejected",
        lambda: compile_config(dropins, configs),
        "namespace is assembly-owned",
    )


if __name__ == "__main__":
    test_compile()
    test_validation()
