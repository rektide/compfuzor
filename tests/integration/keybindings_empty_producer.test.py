#!/usr/bin/env python3
"""Populated -> empty producer updates exact membership without pruning files."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from keybindings.fixtures import isolate_xdg

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generated", ROOT / "tests/integration/keybindings_generated.test.py")
generated = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generated)

def test_empty_producer():
    scratch = ROOT / ".test-agent/keybindings-empty-producer"
    scratch.mkdir(parents=True, exist_ok=True)
    if not (scratch / "README.md").exists():
        (scratch / "README.md").write_text("# Empty producer scratch\nStock generated installers; isolated membership removal, no pruning/live configs.\n")
    with tempfile.TemporaryDirectory(prefix="empty-", dir=scratch) as tmp:
        area = Path(tmp)
        home = area / "home"
        home.mkdir()
        node = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()
        env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "TMPDIR": str(scratch), "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "PATH": os.pathsep.join([str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin", str(Path.home() / ".local/share/pnpm")])}
        env.pop("DIR", None)
        isolate_xdg(env, home)
        host = generated.render(area / "host", "empty-host", {"KEYBINDING_CONSUMERS": {target: {"baseline": [], "placement": "link"} for target in ["niri", "umbriel"]}}, env)
        generated.run([str(host / "bin/install-user.sh")], env)
        targets = {target: {"consumer": str(host)} for target in ["niri", "umbriel"]}
        def declarations(name, chord):
            return {"KEYBINDING_ACTIONS": {name: {"exec": ["echo", name]}}, "KEYBINDINGS": {name: {"action": name, "keys": [chord]}}, "KEYBINDING_TARGETS": targets}
        first = generated.render(area / "first", "remove-me", declarations("remove-me", "Mod+D"), env)
        second = generated.render(area / "second", "keep-me", declarations("keep-me", "Mod+F"), env)
        generated.run([str(first / "bin/install-user.sh")], env)
        generated.run([str(second / "bin/install-user.sh")], env)
        first = generated.render(area / "first", "remove-me", {"KEYBINDING_ACTIONS": {}, "KEYBINDINGS": {}, "KEYBINDING_TARGETS": targets}, env)
        manifest = json.loads((first / "etc/keybinding-producer.json").read_text())
        assert manifest["producer"] == "remove-me" and manifest["resources"] == []
        assert (first / "etc/action/remove-me.yaml").exists()
        generated.run([str(first / "bin/install-user.sh")], env)
        for target, extension in [("niri", "kdl"), ("umbriel", "toml")]:
            base = home / ".config" / target
            state = json.loads((base / ".keybindings/membership.json").read_text())
            assert state["groups"]["remove-me"]["resources"] == []
            assert {resource["id"] for resource in state["groups"]["keep-me"]["resources"]} == {"keep-me"}
            root = (base / f"config.{extension}").read_text()
            assert "remove-me start" not in root and root.count(f"keybinding/{target}/keep-me start") == 1
            assert (base / ".keybindings/source/remove-me/keybinding/remove-me.yaml").exists()
            assert (base / "keybindings" / f"remove-me.binding.{extension}").exists()
        print("ok: actual empty producer reinstall replaces manifest/membership, removes only its blocks, retains other producer and stale physical files")

if __name__ == "__main__":
    test_empty_producer()
