"""Deck host-layer proof: steamos-niri.opt.pb as consumer host + own user layer.

Renders the real opt-typed deck playbook, then runs its user-default install.mjs
against isolated homes in both shapes the deck actually sees:

* an EXISTING root mimicking a previously managed deck: an output block,
  a personal bind, and the old config-overlay.kdl include line -- adoption
  must append the managed insertion area, retire exactly the include line,
  preserve the rest, and assemble the declared deck binds inside the area;
* a FRESH root -- the minimal skeleton plus the same assembled binds.

Also checks the deployment is host-only (no producer manifest), that the
authored adoption body keeps exactly one generated child, and native
validation with the installed niri binary.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location("consumer_hosts", ROOT / "tests/integration/keybindings_consumer_hosts.test.py")
consumer_hosts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer_hosts)

run = consumer_hosts.run
render_playbook = consumer_hosts.render_playbook
consumer_env = consumer_hosts.consumer_env

SCRATCH = ROOT / ".test-agent/keybindings-steamos-niri"

DECK_BINDS = {
    "deck-terminal": ('"Mod+T"', 'spawn "ghostty";', 'hotkey-overlay-title="Open a Terminal: ghostty"'),
    "deck-steam-couch": ('"Mod+G"', 'spawn "sh" "-c" "gamescope -W 1280 -H 800 -f -e -- steam -gamepadui -steamdeck";', None),
    "deck-brightness-down": ('"XF86MonBrightnessDown"', 'spawn "brightnessctl" "set" "5%-";', None),
    "deck-brightness-up": ('"XF86MonBrightnessUp"', 'spawn "brightnessctl" "set" "+5%";', None),
    "deck-volume-up": ('"XF86AudioRaiseVolume"', 'spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+";', None),
    "deck-volume-down": ('"XF86AudioLowerVolume"', 'spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";', None),
    "deck-volume-mute": ('"XF86AudioMute"', 'spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";', None),
}


def assembled_binds(home: Path) -> str:
    generated = home / ".config/niri/.keybindings/generated/niri"
    parts = [(generated / f"{name}.binding.kdl").read_text() for name in DECK_BINDS]
    return "\n".join(parts)


def test_steamos_niri_host_layer() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text(
            "# steamos-niri keybindings scratch\nIsolated real-playbook deck fixtures; no live config changes.\n"
        )
    with tempfile.TemporaryDirectory(prefix="deck-", dir=SCRATCH) as tmp:
        area = Path(tmp)
        host = render_playbook("steamos-niri.opt.pb", "deck-host", etc_typed=False)

        # Host-only deployment: a consumer profile, no producer manifest,
        # and the authored aggregate keeps exactly one generated child.
        assert (host / "etc/keybinding-niri.json").is_file()
        assert not (host / "etc/keybinding-producer.json").exists()
        aggregate = (host / "bin/install-user.sh").read_text()
        assert aggregate.count("actions children") == 1
        assert "config-overlay.kdl" in aggregate and "add-wants niri.service mako.service" in aggregate
        # The deck's old hand-written overlay is gone from declarations.
        assert not (host / "etc/config-overlay.kdl").exists()
        action_spec = json.loads((host / "etc/compfuzor-actions/spec.json").read_text())
        assert action_spec["actions"]["install"]["entry"] == "install-user.mjs"
        assert (host / "bin/install-system.mjs").is_symlink()
        assert not (host / "bin/assemble-system.mjs").exists()

        # EXISTING root: output block + old overlay include + personal bind.
        existing_home = area / "home-existing"
        niri_dir = existing_home / ".config/niri"
        niri_dir.mkdir(parents=True)
        (niri_dir / "config.kdl").write_text(
            'output "eDP-1" { scale 2.0; }\n'
            'include "/opt/steamos-niri-main/etc/config-overlay.kdl"\n'
            'binds { Mod+P { spawn "wlogout"; }; }\n'
        )
        env = consumer_env(existing_home)
        run([str(host / "bin/install.mjs")], env)
        assert Path(env["SERVICE_TEST_TRACE"]).read_text().strip() == "--user add-wants niri.service mako.service"

        root = (niri_dir / "config.kdl").read_text()
        assert 'output "eDP-1" { scale 2.0; }' in root and 'spawn "wlogout";' in root
        assert "config-overlay.kdl" not in root
        assert "// compfuzor-keybindings-begin" in root and root.index("// compfuzor-keybindings-begin") > root.index("wlogout")
        binds = assembled_binds(existing_home)
        for name, (chord, action, title) in DECK_BINDS.items():
            assert chord in binds and action in binds, name
            if title:
                assert title in binds, name
            assert f"keybinding/niri/{name} start" in root, name

        # FRESH root: skeleton + the same assembled binds.
        fresh_home = area / "home-fresh"
        fresh_env = consumer_env(fresh_home)
        run([str(host / "bin/install.mjs")], fresh_env)
        fresh_root = (fresh_home / ".config/niri/config.kdl").read_text()
        assert "compfuzor-keybindings-begin" in fresh_root
        fresh_binds = assembled_binds(fresh_home)
        assert all(chord in fresh_binds and action in fresh_binds for chord, action, _ in DECK_BINDS.values())

        # Host layer is not a membership group: no producer registered.
        membership = fresh_home / ".config/niri/.keybindings/membership.json"
        if membership.exists():
            state = json.loads(membership.read_text())
            assert state.get("groups", {}) == {}

        # Idempotence: a second run changes nothing semantic.
        before = (niri_dir / "config.kdl").read_text()
        run([str(host / "bin/install.mjs")], env)
        assert (niri_dir / "config.kdl").read_text() == before

        if subprocess.run(["sh", "-c", "command -v niri"], capture_output=True).returncode == 0:
            for home in [existing_home, fresh_home]:
                subprocess.run(["niri", "validate", "-c", str(home / ".config/niri/config.kdl")], env=env, check=True, capture_output=True)
        print("ok: steamos-niri host layer — adoption, overlay retirement, declared deck binds, idempotence, native validation")


if __name__ == "__main__":
    test_steamos_niri_host_layer()
