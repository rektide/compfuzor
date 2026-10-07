#!/usr/bin/env python3
import sys
sys.path.insert(0, "library/filter_plugins")
from ansible.errors import AnsibleFilterError
from keybindings_compile import compile_keybindings
from config_compile import compile_config, publish_config, config_runtime_packages

def test_compile():
    result = compile_keybindings({"launch-action": {"exec": ["app", "toggle"]}}, {"launch": {"action": "launch-action", "keys": ["Mod+D"], "umbriel": {"keys": ["Mod+Space"]}}}, {}, {"niri": {"consumer": "/opt/desktop"}, "umbriel": {"consumer": "/opt/desktop"}}, "producer", "/opt/app/etc", "/opt/app/bin")
    files = {file["name"]: file for file in result["files"]}
    assert files["action/launch-action.yaml"]["yaml"]["id"] == "launch-action"
    assert files["keybinding/launch.yaml"]["yaml"]["umbriel"]["keys"] == ["Mod+Space"]
    assert files["keybinding-producer.json"]["json"]["resources"] == [{"path": "/opt/app/etc/action/launch-action.yaml"}, {"path": "/opt/app/etc/keybinding/launch.yaml"}]
    entries = [bin for bin in result["bins"] if bin["name"] == "install-keybindings.sh"]
    assert len(entries) == 1 and entries[0]["scope"] == ["user"] and entries[0]["run"] is False
    assert "install-offer" in entries[0]["content"] and "--selection" in entries[0]["content"]
    assert files["keybindings/selection.json"]["json"]["receivers"] == [
        {"id": "niri", "profile": {"path": "/opt/desktop/etc/keybinding-niri.json"}},
        {"id": "umbriel", "profile": {"path": "/opt/desktop/etc/keybinding-umbriel.json"}}]
    assert any(bin["name"] == "register-keybindings-provider.sh" and bin["compose"] is False for bin in result["bins"])
    assert all(bin.get("run") is False for bin in result["bins"] if bin["name"] == "config/run.sh")
    ordinary = publish_config({}, compile_config({"x": {"processor": "concat"}}, "/etc"))["config"]["contrib"]["PKGS"]
    assert result["pkgs"] == ordinary == config_runtime_packages() == ["jq"]
    runtime = compile_keybindings({"a": {"exec": ["app"]}}, {"b": {"action": "a", "keys": ["Mod+D"]}}, {}, {"niri": {"consumer": "${XDG_CONFIG_HOME}/niri/keybinding-niri.json"}}, "app", "/opt/app/etc", "/opt/app/bin")
    assert next(file["json"] for file in runtime["files"] if file["name"] == "keybindings/selection.json")["receivers"][0]["profile"] == {"path": "${XDG_CONFIG_HOME}/niri/keybinding-niri.json"}
    host = compile_keybindings({}, {"launch": {"patch": True, "keys": ["Alt+D"]}}, {"niri": {"contexts": {"user": {"scope": "user", "root": "config", "subpath": "niri"}}, "native_sources": [{"id": "own", "path": "own.kdl"}]}}, None, "host", "/opt/host/etc", "/opt/host/bin")
    profile = next(file["json"] for file in host["files"] if file["name"] == "keybinding-niri.json")
    assert profile["contexts"]["user"]["root"] == {"path": "${XDG_CONFIG_HOME}"}
    assert profile["userSources"][0]["whenPresent"] is True
    assert profile["nativeSources"][0]["path"] == {"relative": "own.kdl"}
    assert " host " in " " + next(bin["content"] for bin in host["bins"] if bin["name"] == "install-keybindings-niri.sh")
    combined = compile_keybindings({"a": {"exec": ["app"]}}, {"b": {"action": "a", "keys": ["Mod+D"]}}, {"niri": {}}, ["niri"], "both", "/opt/both/etc", "/opt/both/bin")
    assert next(file["json"] for file in combined["files"] if file["name"] == "keybinding-niri.json")["userSources"] == []
    empty = compile_keybindings({}, {}, {}, {"niri": {"consumer": "/opt/desktop"}}, "producer", "/opt/app/etc", "/opt/app/bin")
    assert next(file["json"] for file in empty["files"] if file["name"] == "keybinding-producer.json")["resources"] == []
    assert " install-offer " in " " + next(bin["content"] for bin in empty["bins"] if bin["name"] == "install-keybindings.sh")
    host_only = compile_keybindings({}, {}, {"niri": {}}, None, "host", "/opt/host/etc", "/opt/host/bin")
    assert not any(file["name"] == "keybinding-producer.json" for file in host_only["files"])
    assert " host " in " " + next(bin["content"] for bin in host_only["bins"] if bin["name"] == "install-keybindings-niri.sh")
    assert host_only["pkgs"] == ["jq"]
    combined_runtime = compile_keybindings({}, {}, {"niri": {}}, None, "host", "/etc", "/bin", has_configs=True)
    assert combined_runtime["pkgs"] == ["jq"]
    arbitrary = compile_keybindings({}, {}, {"deck-main": {"adapter": "niri", "contexts": {"user": {"scope": "user", "root": "config", "subpath": "deck"}}}}, None, "host", "/opt/deck/etc", "/opt/deck/bin")
    descriptor = next(file["json"] for file in arbitrary["files"] if file["name"] == "keybindings/consumers/user/deck-main.json")
    assert descriptor["id"] == "deck-main" and descriptor["adapter"] == "niri"
    assert descriptor["profile"] == {"path": "/opt/deck/etc/keybinding-deck-main.json"}
    assert any(bin["name"] == "register-keybindings-consumer-deck-main-user.sh" for bin in arbitrary["bins"])
    no_delivery = compile_keybindings({}, {}, {}, [], "empty", "/opt/empty/etc", "/opt/empty/bin")
    assert next(file["json"] for file in no_delivery["files"] if file["name"] == "keybindings/selection.json")["receivers"] == []
    default = compile_keybindings({}, {}, {}, None, "all", "/opt/all/etc", "/opt/all/bin")
    assert next(file["json"] for file in default["files"] if file["name"] == "keybindings/selection.json")["receivers"] is None
    try:
        compile_keybindings({}, {"launch": {"id": "different"}}, {}, ["niri"], "app", "/etc", "/bin")
    except AnsibleFilterError as error:
        assert "conflicts" in str(error)
    else:
        raise AssertionError("conflicting id accepted")
    print("ok: automatic singular resources, stock workers, declared profiles and scoped installers")

if __name__ == "__main__":
    test_compile()
