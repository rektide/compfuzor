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
    return {
        "opencode.json": {
            "processor": "json-deep-merge",
            "inputs": [
                {"file": "base.json"},
                {"glob": "core/*.json", "name": "core"},
                {"glob": "mcp/*.json", "name": "mcp", "remote": True},
            ],
        },
        "zimfw.conf": {
            "processor": "block-in-file",
            "remote": True,
            "block": {"after": "EOF", "remove_match": ["^legacy-zim-"]},
        },
        "policy.conf": {
            "processor": "concat",
            "disabled_suffix": False,
            "validate": 'test -s "$CONFIG_CANDIDATE"',
            "inputs": [{"glob": "policy.d/*.conf"}],
        },
    }


def test_compile():
    plan = compile_config(fixture(), "/srv/app/etc", "/srv/app/bin", ".disabled")
    configs = plan["spec"]["configs"]

    check("config names", list(configs), ["opencode", "zimfw", "policy"])
    check("filename output", configs["opencode"]["output"], "/srv/app/etc/opencode.json")
    check("file canonicalization", configs["opencode"]["inputs"][0]["file"], "/srv/app/etc/base.json")
    check("glob canonicalization", configs["opencode"]["inputs"][1]["glob"], "/srv/app/etc/core/*.json")
    check("common disabled suffix", configs["opencode"]["inputs"][1]["disabled_suffix"], ".disabled")
    check("inferred glob", configs["zimfw"]["inputs"][0]["glob"], "/srv/app/etc/zimfw.conf.d/*.conf")
    check("derived namespace", configs["zimfw"]["block"]["namespace"], "zimfw")
    check("config remote chooses first glob", configs["zimfw"]["inputs"][0]["remote"], True)
    check("remote registry", plan["spec"]["remotes"]["zimfw.conf.d"]["config"], "zimfw")
    check("disabled suffix false", configs["policy"]["inputs"][0]["disabled_suffix"], None)
    check("candidate validation", configs["policy"]["validate"], 'test -s "$CONFIG_CANDIDATE"')
    check(
        "glob directories contributed",
        {
            "/srv/app/etc/core",
            "/srv/app/etc/mcp",
            "/srv/app/etc/zimfw.conf.d",
            "/srv/app/etc/policy.d",
        }.issubset(set(plan["dirs"])),
        True,
    )

    names = [item["name"] for item in plan["bins"]]
    check("flat leaf exists", "internal/config/opencode" in names, True)
    check("final internal runner emitted directly", "config/run.sh" in names, True)
    check("legacy recipe command absent", "config-opencode.sh" in names, False)
    check("legacy input toggle absent", "disable-mcp.sh" in names, False)
    check("built remote implementation", "config-remote.mjs" in names, True)
    check("single remote implementation", len([name for name in names if name.startswith("config-remote")]), 1)
    check("immutable toggle absent", "disable-policy.d.sh" in names, False)
    leaf = next(item for item in plan["bins"] if item["name"] == "internal/config/opencode")
    check("leaf shares processor", leaf["link"], "config/processors/json-deep-merge")
    check("compiler contributes no legacy statuses", plan["statuses"], [])

    published = publish_config({"other": {"spec": "preserved"}}, plan)
    check("unrelated subsystem preserved", published["other"]["spec"], "preserved")
    check("normalized spec published", published["config"]["spec"], plan["spec"])
    check("spec file contributed", published["config"]["contrib"]["ETC_FILES"][-1]["name"], "config.spec.json")


def test_validation():
    plan = compile_config({"app.json": {"processor": "json-deep-merge", "inputs": [{
        "glob": "portable/*.json", "remote": True,
        "place": {"at": "mcp.servers", "as": "object"},
        "envsubst": {"file": "../env.export"},
    }]}}, "/etc")
    check("placement compiled", plan["spec"]["configs"]["app"]["inputs"][0]["place"], {"at": "mcp.servers", "as": "object"})
    check("envsubst compiled", plan["spec"]["configs"]["app"]["inputs"][0]["envsubst"], {"file": "../env.export"})
    for item, message in [
        ({"place": {"at": "mcp..servers", "as": "object"}}, "dotted path"),
        ({"place": {"at": "mcp", "as": "something"}}, "must be object or array"),
        ({"place": {"at": "mcp"}}, "exactly 'at' and 'as'"),
        ({"envsubst": {"file": ""}}, "non-empty file path"),
    ]:
        check_raises("invalid JSON input transform", lambda item=item: compile_config({
            "app.json": {"processor": "json-deep-merge", "inputs": [{"glob": "d/*.json", **item}]}
        }, "/etc"), message)
    check_raises("non-JSON placement", lambda: compile_config({
        "app.conf": {"processor": "concat", "inputs": [{"glob": "d/*.conf", "place": {"at": "x", "as": "object"}}]}
    }, "/etc"), "require the json-deep-merge processor")
    check_raises("file placement needs slot", lambda: compile_config({
        "app.json": {"processor": "json-deep-merge", "inputs": [{"file": "x.json", "place": {"at": "mcp", "as": "object"}}]}
    }, "/etc"), "requires a glob input")
    check_raises(
        "removed artifact input",
        lambda: compile_config({"x.conf": {"processor": "concat", "inputs": [{"artifact": "y"}]}}, "/etc"),
        "exactly one file or glob",
    )
    check_raises(
        "removed anchor setting",
        lambda: compile_config({"x.conf": {"processor": "block-in-file", "block": {"anchor": "eof:100"}}}, "/etc"),
        "unknown settings: anchor",
    )
    check_raises(
        "placement conflict",
        lambda: compile_config({"x.conf": {"processor": "block-in-file", "block": {"before": "BOF", "after": "EOF"}}}, "/etc"),
        "conflicting placement",
    )
    check_raises(
        "duplicate derived name",
        lambda: compile_config({"a/x.conf": {"processor": "concat"}, "b/x.conf": {"processor": "concat"}}, "/etc"),
        "duplicate config name",
    )


if __name__ == "__main__":
    test_compile()
    test_validation()
