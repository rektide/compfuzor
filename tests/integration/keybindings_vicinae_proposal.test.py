#!/usr/bin/env python3
"""Executable isolated proposal; it neither starts Vicinae nor cuts over playbooks."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generated", ROOT / "tests/integration/keybindings_generated.test.py")
generated = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generated)

def test_proposal():
    scratch = ROOT / ".test-agent/keybindings-vicinae-proposal"
    scratch.mkdir(parents=True, exist_ok=True)
    if not (scratch / "README.md").exists():
        (scratch / "README.md").write_text("# Vicinae proposal scratch\nIsolated generated consumer fixtures; no live app/config changes.\n")
    with tempfile.TemporaryDirectory(prefix="proposal-", dir=scratch) as tmp:
        area = Path(tmp)
        home = area / "home"
        node = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()
        env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "TMPDIR": str(scratch), "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "PATH": os.pathsep.join([str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin", str(Path.home() / ".local/share/pnpm")])}
        env.pop("DIR", None)
        consumers = {}
        for target in ["niri", "umbriel"]:
            baseline = area / ("baseline.kdl" if target == "niri" else "baseline.toml")
            baseline.write_text('binds { Mod+B { spawn "echo" "base"; }; }\n' if target == "niri" else '[keybinds]\n"Mod+B" = "spawn:echo base"\n')
            consumers[target] = {"baseline": [str(baseline)], "placement": "link"}
        host = generated.render(area / "host", "proposal-host", {"KEYBINDING_CONSUMERS": consumers, "KEYBINDINGS": {"vicinae-clipboard": {"patch": True, "umbriel": {"keys": ["Mod+Grave"]}}}}, env)
        declarations = yaml.safe_load((ROOT / "examples/keybindings/vicinae.yaml").read_text())
        declarations["KEYBINDING_TARGETS"] = {target: {"consumer": str(host)} for target in consumers}
        producer = generated.render(area / "producer", "vicinae-proposal", declarations, env)
        generated.run([str(producer / "bin/install-user.sh")], env)
        niri = home / ".config/niri/.keybindings/generated/niri"
        umbriel = home / ".config/umbriel/.keybindings/generated/umbriel"
        for name, chord in [("vicinae-launch", "Mod+D"), ("vicinae-clipboard", "Alt+Grave"), ("vicinae-switch-windows", "Mod+F")]:
            assert json.dumps(chord) in (niri / f"{name}.binding.kdl").read_text()
        for name, chord in [("vicinae-launch", "Mod+Space"), ("vicinae-clipboard", "Mod+Grave"), ("vicinae-switch-windows", "Mod+Slash")]:
            assert json.dumps(chord) in (umbriel / f"{name}.binding.toml").read_text()
        assert "?toggle=true" not in (niri / "vicinae-switch-windows.binding.kdl").read_text()
        assert "?toggle=true" in (umbriel / "vicinae-switch-windows.binding.toml").read_text()
        print("ok: isolated Vicinae proposed chords, shared modern routes and intentional toggle policy")

if __name__ == "__main__":
    test_proposal()
