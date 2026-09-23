#!/usr/bin/env python3

import sys

sys.path.insert(0, "library/filter_plugins")

from ansible.errors import AnsibleFilterError
from config_compile import compile_config
from config_context_compile import compile_config_contexts
from zim_context_compile import compile_zim_contexts


def config_plan():
    base = compile_config(
        {
            "zimrc": {"processor": "concat", "inputs": [{"glob": "zimrc.d/*.conf", "name": "zimrc"}]},
            "zimenv": {"processor": "concat", "inputs": [{"glob": "zimenv.d/*.conf", "name": "zimenv"}]},
        },
        "/opt/zim/etc",
        "/opt/zim/bin",
    )
    return compile_config_contexts(
        base,
        {
            "user": {"scope": "user", "root": "config", "configs": ["zimrc", "zimenv"]},
            "system": {"scope": "system", "root": "/scratch/config", "configs": ["zimrc", "zimenv"]},
        },
        "/opt/zim/etc",
        "/opt/zim/bin",
        "user",
        "zim",
    )


def test_compile_zim_contexts():
    plan = config_plan()
    compiled = compile_zim_contexts(
        {
            "user": {"config": "user"},
            "system": {
                "config": "system",
                "loader_root": "/scratch/startup",
                "zimrc_home": "/scratch/cache/zim",
                "zimenv_home": "/scratch/cache/zimenv",
                "registry": "/scratch/registry/zimfw.conf",
            },
        },
        plan["spec"],
        "user",
        "/opt/zim/etc",
        "/opt/zim",
        "/opt/zim/bin",
        "zim-main",
        plan["bins"],
    )
    assert compiled["spec"]["defaultContext"] == "user"
    assert compiled["spec"]["version"] == 2
    assert compiled["spec"]["canonical"] == {
        "zimrc": "/opt/zim/etc/zimrc",
        "zimenv": "/opt/zim/etc/zimenv",
        "zimrcLegacy": ["/opt/zim/etc/zimrc", "/opt/zim/etc/zimrc"],
        "zimenvLegacy": ["/opt/zim/etc/zimenv", "/opt/zim/etc/zimenv"],
        "zimrcLoaderTemplate": "/opt/zim/etc/zimrc.zsh",
        "zimenvLoaderTemplate": "/opt/zim/etc/zimenv.zsh",
        "controller": "/opt/zim/src/zimfw.zsh",
        "emergencyModule": "/opt/zim/etc/zim-modules/emergency/init.zsh",
        "registry": "/opt/zim/etc/zimrc",
        "blockPrefix": "zim-main",
    }
    assert compiled["spec"]["contexts"]["user"]["loader_root"] == {
        "env": "ZDOTDIR", "default": {"path": "${HOME}"}
    }
    assert "zshenv" not in compiled["spec"]["contexts"]["user"]
    assert "zshrc" not in compiled["spec"]["contexts"]["user"]
    assert "wire_remove" not in compiled["spec"]["contexts"]["user"]
    assert compiled["spec"]["contexts"]["system"]["scope"] == "system"
    by_name = {record["name"]: record for record in compiled["bins"]}
    assert set(by_name) == {"compfuzor-runtime.mjs", "zim/install.mjs", "install-zim.sh", "status-zim.sh"}
    assert by_name["compfuzor-runtime.mjs"]["src"].endswith("/runtime/compfuzor-runtime.mjs")
    assert by_name["zim/install.mjs"]["link"] == "compfuzor-runtime.mjs"
    assert by_name["install-zim.sh"]["action"] == "install"
    assert "scope" not in by_name["install-zim.sh"]
    assert [record["name"] for record in compiled["bins"] if record.get("link")] == ["zim/install.mjs"]
    assert compiled["statuses"] == [{"name": "status-zim.sh", "args": ["--activation-only"], "exit2": "error"}]
    assert compiled["etc_files"][0]["name"] == "zim.spec.json"

    system_default = compile_zim_contexts(
        {
            "user": {"config": "user"},
            "system": {
                "config": "system",
                "loader_root": "/scratch/startup",
                "zimrc_home": "/scratch/cache/zim",
                "zimenv_home": "/scratch/cache/zimenv",
                "registry": "/scratch/registry/zimfw.conf",
            },
        },
        plan["spec"], "system", "/opt/zim/etc", "/opt/zim", "/opt/zim/bin", "zim-main", plan["bins"],
    )
    assert "scope" not in next(record for record in system_default["bins"] if record["name"] == "install-zim.sh")
    assert {record["name"] for record in system_default["bins"]} == set(by_name)


def test_compile_zim_contexts_dotfile_wiring():
    plan = config_plan()
    compiled = compile_zim_contexts(
        {
            "user": {
                "config": "user",
                "zshenv": "${HOME}/.zshenv",
                "zshrc": "${HOME}/.zshrc",
                "wire_remove": ["^zim-main-zimenv$", "^zim-main-zimrc$"],
            },
        },
        plan["spec"],
        "user",
        "/opt/zim2/etc",
        "/opt/zim2",
        "/opt/zim2/bin",
        "zim2-main",
        plan["bins"],
    )
    context = compiled["spec"]["contexts"]["user"]
    assert context["zshenv"] == {"path": "${HOME}/.zshenv"}
    assert context["zshrc"] == {"path": "${HOME}/.zshrc"}
    assert context["wire_remove"] == ["^zim-main-zimenv$", "^zim-main-zimrc$"]


def test_compile_zim_contexts_wiring_validation():
    plan = config_plan()
    check_raises(
        lambda: compile_zim_contexts(
            {"user": {"config": "user", "wire_remove": "zim-main-"}},
            plan["spec"], "user", "/opt/zim/etc", "/opt/zim", "/opt/zim/bin", "zim-main", plan["bins"],
        ),
        "wire_remove must be a list",
    )
    check_raises(
        lambda: compile_zim_contexts(
            {"user": {"config": "user", "zshenv": "relative/path"}},
            plan["spec"], "user", "/opt/zim/etc", "/opt/zim", "/opt/zim/bin", "zim-main", plan["bins"],
        ),
        "zshenv",
    )


def check_raises(operation, expected):
    try:
        operation()
    except AnsibleFilterError as error:
        assert expected in str(error), error
    else:
        raise AssertionError("expected compile error")


def test_validation():
    plan = config_plan()
    check_raises(
        lambda: compile_zim_contexts({"user": {"config": "user"}}, plan["spec"], "missing", "/e", "/d", "/b", "n", []),
        "ZIM_CONTEXT",
    )
    check_raises(
        lambda: compile_zim_contexts({"system": {"config": "system"}}, plan["spec"], "system", "/e", "/d", "/b", "n", []),
        "system context requires",
    )
    check_raises(
        lambda: compile_zim_contexts({"bad/context": {"config": "user"}}, plan["spec"], "bad/context", "/e", "/d", "/b", "n", []),
        "context names",
    )
    check_raises(
        lambda: compile_zim_contexts({"donor": {"config": "user"}}, plan["spec"], "donor", "/e", "/d", "/b", "n", []),
        "role command",
    )
    check_raises(
        lambda: compile_zim_contexts({"user": {"config": "user"}}, plan["spec"], "user", "/e", "/d", "/b", "n", [{"name": "install-zim.sh"}]),
        "collision",
    )
    check_raises(
        lambda: compile_zim_contexts({"user": {"config": "user"}}, plan["spec"], "user", "/e", "/d", "/b", "n", [{"name": "install-zim-donor.sh"}]),
        "collision",
    )


if __name__ == "__main__":
    test_compile_zim_contexts()
    test_validation()
    print("ok: Zim activation context compiler")
