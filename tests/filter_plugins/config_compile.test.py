#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from config_compile import compile_config


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
        "policy": {
            "root": "/srv/app/etc",
            "assemblies": {
                "main": {
                    "output": "policy.conf",
                    "processor": "concat",
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
        ["/srv/app/etc/core.d", "/srv/app/etc/mcp", "/srv/app/etc/policy.d"],
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

    names = [item["name"] for item in plan["bins"]]
    check(
        "generated command names",
        names,
        [
            "config.sh",
            "config-app.sh",
            "disable-app.sh",
            "enable-app.sh",
            "status-config-app.sh",
            "config-policy.sh",
            "status-config-policy.sh",
        ],
    )
    check("status names", plan["statuses"], ["status-config-app.sh", "status-config-policy.sh"])


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


if __name__ == "__main__":
    test_compile()
    test_validation()
