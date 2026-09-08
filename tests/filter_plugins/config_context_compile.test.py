#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from config_compile import compile_config
from config_context_compile import compile_config_contexts


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


def base_plan():
    return compile_config(
        {
            "outputs/app.conf": {
                "processor": "concat",
                "inputs": [
                    {"file": "inputs/base.conf"},
                    {"glob": "inputs/app.d/*.conf", "name": "fragments"},
                ],
            },
            "outputs/settings.json": {
                "processor": "json-deep-merge",
                "inputs": [{"glob": "inputs/settings.d/*.json"}],
            },
        },
        "/opt/example/etc",
        "/opt/example/bin",
    )


def test_compile_contexts():
    original = base_plan()
    compiled = compile_config_contexts(
        original,
        {
            "user": {
                "scope": "user",
                "root": "config",
                "subpath": "example",
                "install": "assemble",
                "dropins": "link",
                "configs": {
                    "app": {
                        "output": {"env": "APP_CONFIG", "default": "outputs/app.conf"},
                        "inputs": {"fragments": "local/app.d"},
                    }
                },
            },
            "system-test": {
                "scope": "system",
                "root": "/scratch/system config",
            },
        },
        "/opt/example/etc",
        "/opt/example/bin",
    )

    check("base plan is pure", "contexts" in original["spec"], False)
    user = compiled["spec"]["contexts"]["user"]
    check("user class root", user["root"], {"path": "${XDG_CONFIG_HOME}"})
    check("context subpath", user["subpath"], "example")
    check("context install default", user["install"], "assemble")
    check("context drop-in default", user["dropins"], "link")
    check("context selection", list(user["configs"]), ["app"])
    check(
        "output environment selector",
        user["configs"]["app"]["output"],
        {"env": "APP_CONFIG", "default": {"relative": "outputs/app.conf"}},
    )
    check("ETC file keeps relative path", user["configs"]["app"]["inputs"][0], {"relative": "inputs/base.conf"})
    check("named input override", user["configs"]["app"]["inputs"][1], {"relative": "local/app.d"})
    system = compiled["spec"]["contexts"]["system-test"]
    check("exact root", system["root"], {"path": "/scratch/system config"})
    check("omitted configs selects all", list(system["configs"]), ["app", "settings"])
    check("derived output", system["configs"]["settings"]["output"], {"relative": "outputs/settings.json"})

    bins = {item["name"]: item for item in compiled["bins"]}
    check("shared context runtime", bins["config-context.ts"]["raw"], True)
    check("shared context module", bins["config/context.ts"]["raw"], True)
    check("shared toolkit module", bins["config/toolkit.ts"]["raw"], True)
    check("shared LINKS delivery module", bins["links/delivery.ts"]["raw"], True)
    check("context module directory", "/opt/example/bin/config" in compiled["dirs"], True)
    check("user entry point", bins["config-user.sh"]["helpers"], False)
    check("system entry point", "config-system-test.sh" in bins, True)
    check("context commands do not compose", bins["config-user.sh"]["compose"], False)
    check("ordinary install composes", "compose" in bins["install-config-user.sh"], False)
    check("user install carries user scope", bins["install-config-user.sh"]["scope"], "user")
    check("system install uses bare scope", "scope" in bins["install-config-system-test.sh"], False)
    check("drop-in refresh does not compose", bins["install-config-user-dropins.sh"]["compose"], False)
    check("whole copy does not compose", bins["install-config-user-copy.sh"]["compose"], False)
    check("input command does not compose", bins["config-inputs-user.sh"]["compose"], False)
    check("context status is registered", "status-config-context-user.sh" in compiled["statuses"], True)
    check("context status adapts reporter errors", 'exit 1' in bins["status-config-context-user.sh"]["content"], True)


def test_validation():
    check_raises(
        "scope required",
        lambda: compile_config_contexts(base_plan(), {"user": {"root": "config"}}, "/opt/example/etc", "/opt/example/bin"),
        "scope must be user or system",
    )
    check_raises(
        "root required",
        lambda: compile_config_contexts(base_plan(), {"user": {"scope": "user"}}, "/opt/example/etc", "/opt/example/bin"),
        "root is required",
    )
    check_raises(
        "unknown config",
        lambda: compile_config_contexts(
            base_plan(), {"user": {"scope": "user", "root": "config", "configs": ["missing"]}}, "/opt/example/etc", "/opt/example/bin"
        ),
        "unknown config",
    )
    check_raises(
        "relative root rejected",
        lambda: compile_config_contexts(
            base_plan(), {"user": {"scope": "user", "root": "relative"}}, "/opt/example/etc", "/opt/example/bin"
        ),
        "must be absolute",
    )
    check_raises(
        "unknown runtime root rejected",
        lambda: compile_config_contexts(
            base_plan(), {"user": {"scope": "user", "root": "${OTHER}/path"}}, "/opt/example/etc", "/opt/example/bin"
        ),
        "unsupported runtime expression",
    )
    check_raises(
        "invalid install default",
        lambda: compile_config_contexts(
            base_plan(), {"user": {"scope": "user", "root": "config", "install": "replace"}}, "/opt/example/etc", "/opt/example/bin"
        ),
        "install must be assemble, copy, or link",
    )

    external = compile_config(
        {"app.conf": {"processor": "concat", "inputs": [{"file": "/outside/base.conf"}]}},
        "/opt/example/etc",
        "/opt/example/bin",
    )
    check_raises(
        "external input requires binding",
        lambda: compile_config_contexts(external, {"user": {"scope": "user", "root": "config"}}, "/opt/example/etc", "/opt/example/bin"),
        "outside ETC",
    )
    rebound = compile_config_contexts(
        external,
        {"user": {"scope": "user", "root": "config", "configs": {"app": {"inputs": {0: "inputs/base.conf"}}}}},
        "/opt/example/etc",
        "/opt/example/bin",
    )
    check("external input explicit binding", rebound["spec"]["contexts"]["user"]["configs"]["app"]["inputs"][0], {"relative": "inputs/base.conf"})

    colliding = base_plan()
    colliding["bins"].append({"name": "config-user.sh"})
    check_raises(
        "generated command collision",
        lambda: compile_config_contexts(colliding, {"user": {"scope": "user", "root": "config"}}, "/opt/example/etc", "/opt/example/bin"),
        "generated command collision",
    )


if __name__ == "__main__":
    test_compile_contexts()
    test_validation()
