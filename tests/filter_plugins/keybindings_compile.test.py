#!/usr/bin/env python3
import sys
sys.path.insert(0, "library/filter_plugins")
from ansible.errors import AnsibleFilterError
from keybindings_compile import compile_keybindings

def test_compile():
    result = compile_keybindings({"launch-action": {"exec": ["app", "toggle"]}}, {"launch": {"action": "launch-action", "keys": ["Mod+D"], "umbriel": {"keys": ["Mod+Space"]}}}, {}, {"niri": {"consumer": "/opt/desktop"}, "umbriel": {"consumer": "/opt/desktop"}}, "producer", "/opt/app/etc", "/opt/app/bin")
    files = {file["name"]: file for file in result["files"]}
    assert files["action/launch-action.yaml"]["yaml"]["id"] == "launch-action"
    assert files["keybinding/launch.yaml"]["yaml"]["umbriel"]["keys"] == ["Mod+Space"]
    assert files["keybinding-producer.json"]["json"]["resources"] == [{"path": "/opt/app/etc/action/launch-action.yaml"}, {"path": "/opt/app/etc/keybinding/launch.yaml"}]
    entries = [bin for bin in result["bins"] if bin["name"].startswith("install-keybindings-")]
    assert len(entries) == 2 and all(entry["scope"] == ["user"] and entry["run"] is False for entry in entries)
    assert all("--profile /opt/desktop/etc/keybinding-" in entry["content"] for entry in entries)
    assert all(bin.get("run") is False for bin in result["bins"] if bin["name"] == "config/run.sh")
    host = compile_keybindings({}, {"launch": {"patch": True, "keys": ["Alt+D"]}}, {"niri": {"contexts": {"user": {"scope": "user", "root": "config", "subpath": "niri"}}, "native_sources": [{"id": "own", "path": "own.kdl"}]}}, None, "host", "/opt/host/etc", "/opt/host/bin")
    profile = next(file["json"] for file in host["files"] if file["name"] == "keybinding-niri.json")
    assert profile["contexts"]["user"]["root"] == {"path": "${XDG_CONFIG_HOME}"}
    assert profile["userSources"][0]["whenPresent"] is True
    assert profile["nativeSources"][0]["path"] == {"relative": "own.kdl"}
    assert " host " in " " + next(bin["content"] for bin in host["bins"] if bin["name"] == "install-keybindings-niri.sh")
    try:
        compile_keybindings({}, {"launch": {"id": "different"}}, {}, ["niri"], "app", "/etc", "/bin")
    except AnsibleFilterError as error:
        assert "conflicts" in str(error)
    else:
        raise AssertionError("conflicting id accepted")
    print("ok: automatic singular resources, stock workers, declared profiles and scoped installers")

if __name__ == "__main__":
    test_compile()
