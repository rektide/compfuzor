#!/usr/bin/env python3
"""Domain controller mappings and complete-operation contributions, without remote discovery."""
import sys
sys.path.insert(0, "library/filter_plugins")
from action_audiences import compile_action_audiences
from config_context_compile import compile_config_contexts
from keybindings_compile import compile_keybindings


def reject(call, text):
    try:
        call()
    except Exception as error:
        assert text in str(error), str(error)
    else:
        raise AssertionError("expected " + text)


def config(contexts, mapping=None, owner="config", policy=None):
    return compile_config_contexts({"spec": {"configs": {"result": {"output": "/deployment/etc/result", "inputs": [{"file": "/deployment/etc/input"}]}}}}, contexts, "/deployment/etc", "/deployment/bin", "desktop", owner, {} if policy is None else policy, mapping)


def test_config():
    contexts = {"desktop": {"scope": "user", "root": "config"}, "laptop": {"scope": "user", "root": "config"}, "host": {"scope": "system", "root": "/host"}}
    reject(lambda: config(contexts), "CONFIG_ACTION_CONTEXTS: ambiguous user")
    compiled = config(contexts, {"user": "desktop"})
    command = next(value for value in compiled["bins"] if value["name"] == "config-assemble.sh")
    assert command["compose"] is False
    assert command["action_operations"][0]["audiences"]["system"]["context"] == "host"
    plan = compile_action_audiences(compiled["bins"], {})["spec"]["actions"]
    assert plan["assemble-config"]["plans"]["user"][0]["domain"] == "config"
    assert plan["install-config"]["plans"]["system"][0]["context"] == "host"
    reject(lambda: config(contexts, {"system": "canonical", "user": "desktop"}), "noncanonical")
    owned = config({"desktop": contexts["desktop"]}, owner="zim")
    install = next(value for value in owned["bins"] if value["name"] == "config-install.sh")
    assert "action_operations" not in install
    assert "install" not in compile_action_audiences(owned["bins"], {})["spec"]["actions"]
    assert "system" not in compile_action_audiences(owned["bins"], {})["spec"]["actions"]["assemble"]["plans"]


def keybindings(consumers, targets=None):
    return compile_keybindings({}, {}, consumers, targets, "producer", "/deployment/etc", "/deployment/bin", context="desktop", audience_policy={})


def test_keybindings():
    contexts = {"desktop": {"scope": "user", "root": "config"}, "laptop": {"scope": "user", "root": "config"}, "host": {"scope": "system", "root": "/host"}}
    reject(lambda: keybindings({"niri": {"contexts": contexts}}), "ambiguous user")
    owned = keybindings({"niri": {"contexts": contexts, "action_contexts": {"user": "desktop"}}})
    descriptor = next(value for value in owned["bins"] if value["name"] == "install-keybindings-niri.sh")
    assert descriptor["scope"] == ["user"] and "--context desktop --scope user" in descriptor["content"]
    operations = descriptor["action_operations"]
    assert [value["action"] for value in operations] == ["install", "assemble"]
    assert operations[1]["audiences"]["system"]["mode"] == "assemble"
    external = keybindings({}, {"niri": {"consumer": {"env": "CONSUMER_PROFILE"}, "context": "desktop", "scope": "user", "action_contexts": {"user": "desktop", "system": "host"}}})
    descriptor = next(value for value in external["bins"] if value["name"] == "install-keybindings.sh")
    assert len(descriptor["action_operations"]) == 1
    assert set(descriptor["action_operations"][0]["audiences"]) == {"user", "system"}
    assert all(value["operation"] == "install-offer" for value in descriptor["action_operations"][0]["audiences"].values())
    selection = next(value["json"] for value in external["files"] if value["name"] == "keybindings/selection.json")
    assert selection["receivers"] == [{"id": "niri", "profile": {"env": "CONSUMER_PROFILE"}, "context": "desktop", "scope": "user", "actionContexts": {"user": "desktop", "system": "host"}}]
    single = keybindings({}, {"niri": {"consumer": {"env": "UNREAD_REMOTE_PROFILE"}, "context": "desktop", "scope": "user"}})
    descriptor = next(value for value in single["bins"] if value["name"] == "install-keybindings.sh")
    assert set(descriptor["action_operations"][0]["audiences"]) == {"user"}


if __name__ == "__main__":
    test_config()
    test_keybindings()
    print("ok: named audience mappings, canonical/ownership exclusions and explicit external assertions")
