#!/usr/bin/env python3
"""End-to-end Vicinae cutover proof over the real consumer/producer playbooks.

Run directly:

    ./tests/integration/keybindings_vicinae_proposal.test.py

Renders niri.etc.pb and umbriel.etc.pb (real consumer hosts) plus
vicinae.src.pb (real producer, existing profile selector overrides point to
isolated consumers while source deployment remains separate). Adopts both roots
with the consumer install.mjs, registers the
producer through its generated target installers, and checks the reviewed
chord outcomes and toggle policy without launching any application.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("consumer_hosts", ROOT / "tests/integration/keybindings_consumer_hosts.test.py")
consumer_hosts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer_hosts)

run = consumer_hosts.run
render_playbook = consumer_hosts.render_playbook
consumer_env = consumer_hosts.consumer_env
SCRATCH = ROOT / ".test-agent/keybindings-vicinae-proposal"


def test_proposal():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text("# Vicinae proposal scratch\nIsolated real-playbook consumer/producer fixtures; no live app/config changes.\n")
    with tempfile.TemporaryDirectory(prefix="proposal-", dir=SCRATCH) as tmp:
        area = Path(tmp)
        niri_host = render_playbook("niri.etc.pb", "proposal-niri-host", etc_typed=True)
        umbriel_host = render_playbook("umbriel.etc.pb", "proposal-umbriel-host", etc_typed=True)
        producer = render_playbook(
            "vicinae.src.pb",
            "proposal-vicinae",
            etc_typed=False,
        )
        # Consumers advertise owner-held descriptions; the producer owns one offer.
        leaf = (producer / "bin/install-keybindings.sh").read_text()
        assert " install-offer " in leaf and "--selection" in leaf and "--registry-policy" in leaf
        assert "--profile" not in leaf and "/etc/opt/" not in leaf
        for target in ["niri", "umbriel"]:
            assert not (producer / f"bin/install-keybindings-{target}.sh").exists()
        assert (producer / "etc/keybinding-producer.json").is_file()
        for hand in ["install-niri.sh", "install-umbriel.sh"]:
            assert not (producer / "bin" / hand).exists()
        assert (producer / "bin/install-kde.sh").is_file()
        aggregate = (producer / "bin/install-user.sh").read_text()
        assert aggregate.count('"$DIR/bin/install-keybindings.sh"') == 1

        # Niri live root mimics the real one: handy + vicinae blocks, a
        # config.d include, and unrelated text; its includes must exist.
        niri_home = area / "home-niri"
        niri_dir = niri_home / ".config/niri"
        (niri_dir / "handy").mkdir(parents=True)
        (niri_dir / "config.d").mkdir(parents=True)
        (niri_dir / "handy/handy.kdl").write_text('binds { Mod+H hotkey-overlay-title="handy" { spawn "echo" "handy"; }; }\n')
        (niri_dir / "config.d/display-alt.kdl").write_text('output "DP-1" { scale 2; }\n')
        (niri_dir / "config.kdl").write_text(
            'output "DP-1" {\n    scale 1\n}\n\n'
            "// handy start\ninclude \"./handy/handy.kdl\"\n// handy end\n"
            '// vicinae start\ninclude "./vicinae/keybinding-launch.kdl"\n// vicinae end\n\n'
            'include "./config.d/display-alt.kdl"\n'
        )
        # Umbriel live files still carry the previously managed bytes.
        umbriel_home = area / "home-umbriel"
        umbriel_dir = umbriel_home / ".config/umbriel"
        umbriel_dir.mkdir(parents=True)
        (umbriel_dir / "config.toml").write_text(consumer_hosts.OLD_CONFIG_TOML)
        (umbriel_dir / "keybinds-local.toml").write_text(consumer_hosts.OLD_KEYBINDS_LOCAL_TOML)

        niri_env = consumer_env(niri_home)
        umbriel_env = consumer_env(umbriel_home)
        # Adopt first (consumer installers), then register the producer.
        run([str(niri_host / "bin/install.mjs")], niri_env)
        run([str(umbriel_host / "bin/install.mjs")], umbriel_env)
        # Producer leaves directly: the authored aggregate body enables a
        # user service. We never execute it; HOME isolation does not isolate DBus.
        run([str(producer / "bin/install-keybindings.sh"), "--target", "niri"], niri_env)
        run([str(producer / "bin/install-keybindings.sh"), "--target", "umbriel"], umbriel_env)

        niri_root = (niri_dir / "config.kdl").read_text()
        assert "vicinae/keybinding-launch.kdl" not in niri_root and "vicinae start" not in niri_root
        assert 'include "./handy/handy.kdl"' in niri_root
        niri_generated = niri_home / ".config/niri/.keybindings/generated/niri"
        for name, chord in [("vicinae-launch", "Mod+D"), ("vicinae-clipboard", "Alt+Grave"), ("vicinae-switch-windows", "Mod+F")]:
            body = (niri_generated / f"{name}.binding.kdl").read_text()
            assert json.dumps(chord) in body and (niri_dir / f"keybindings/{name}.binding.kdl").is_symlink()
            assert f"keybinding/niri/{name} start" in niri_root
        assert "?toggle=true" not in (niri_generated / "vicinae-switch-windows.binding.kdl").read_text()
        assert "vicinae://launch/clipboard/history\"" in (niri_generated / "vicinae-clipboard.binding.kdl").read_text()

        umbriel_root = (umbriel_dir / "config.toml").read_text()
        assert '"Mod+Grave"' not in (umbriel_dir / "keybinds-local.toml").read_text().split("[keybinds]")[1]
        umbriel_generated = umbriel_home / ".config/umbriel/.keybindings/generated/umbriel"
        for name, chord in [("vicinae-launch", "Mod+Space"), ("vicinae-clipboard", "Mod+Grave"), ("vicinae-switch-windows", "Mod+Slash")]:
            body = (umbriel_generated / f"{name}.binding.toml").read_text()
            assert json.dumps(chord) in body and (umbriel_dir / f"keybindings/{name}.binding.toml").is_symlink()
            assert f"keybinding/umbriel/{name} start" in umbriel_root
        assert "?toggle=true" in (umbriel_generated / "vicinae-clipboard.binding.toml").read_text()
        assert "?toggle=true" in (umbriel_generated / "vicinae-switch-windows.binding.toml").read_text()
        assert "?toggle=true" not in (umbriel_generated / "vicinae-launch.binding.toml").read_text()

        for target, home in [("niri", niri_home), ("umbriel", umbriel_home)]:
            state = json.loads((home / f".config/{target}/.keybindings/membership.json").read_text())
            assert set(state["groups"]) == {"vicinae"}
        if subprocess.run(["sh", "-c", "command -v niri"], capture_output=True).returncode == 0:
            subprocess.run(["niri", "validate", "-c", str(niri_dir / "config.kdl")], env=niri_env, check=True, capture_output=True)
        if subprocess.run(["sh", "-c", "command -v umbriel"], capture_output=True).returncode == 0:
            subprocess.run(["umbriel", "validate", "-c", str(umbriel_dir / "config.toml")], env=umbriel_env, check=True, capture_output=True)
        print("ok: real-playbook cutover — adoption, registration, target chords, toggle policy, native validation")


if __name__ == "__main__":
    test_proposal()
