"""Model-implementation proof: the media-keys pure producer over real consumer hosts.

Renders media-keys.etc.pb (declarations only -- no authored target wiring,
ETC_FILES or installer body) plus the real niri.etc.pb / umbriel.etc.pb consumer hosts,
adopts fresh roots, registers the producer through its generic advertised offer
installers, and checks the exact media-key chord/action outcomes for both
compositors: the Surface Dial's Shift+ fine-step chords, plain coarse chords,
add-keys doubling for mute/transport, niri-only allow-when-locked options,
durable membership, and native validation when the compositor binaries exist.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA_VARS = yaml.safe_load((ROOT / "media-keys.etc.pb").read_text())[0]["vars"]
MEDIA_NAME = MEDIA_VARS.get("NAME", MEDIA_VARS["TYPE"] + ("-" + MEDIA_VARS["INSTANCE"] if MEDIA_VARS.get("INSTANCE") else ""))

spec = importlib.util.spec_from_file_location("consumer_hosts", ROOT / "tests/integration/keybindings_consumer_hosts.test.py")
consumer_hosts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer_hosts)

run = consumer_hosts.run
render_playbook = consumer_hosts.render_playbook
consumer_env = consumer_hosts.consumer_env

SCRATCH = ROOT / ".test-agent/keybindings-media-keys"

# The exact spawn fragments each compositor must render for the fine-step
# volume action the Surface Dial's dial rotation uses.
NIRI_FINE_UP = 'spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.01+" "-l" "1.0";'
UMBRIEL_FINE_UP = "spawn:'wpctl' 'set-volume' '@DEFAULT_AUDIO_SINK@' '0.01+' '-l' '1.0'"


def test_media_keys_model_producer() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text(
            "# Media-keys model producer scratch\nIsolated real-playbook consumer/producer fixtures; no live config changes.\n"
        )
    with tempfile.TemporaryDirectory(prefix="media-keys-", dir=SCRATCH) as tmp:
        area = Path(tmp)
        assert "KEYBINDING_TARGETS" not in MEDIA_VARS
        niri_host = render_playbook("niri.etc.pb", "media-keys-niri-host", etc_typed=True)
        umbriel_host = render_playbook("umbriel.etc.pb", "media-keys-umbriel-host", etc_typed=True)
        producer = render_playbook(
            "media-keys.etc.pb",
            "media-keys-producer",
            etc_typed=True,
        )

        # Declarations-only producer: packaged singular YAML, generated
        # installer, one generated offer aggregate, and nothing else authored.
        manifest = json.loads((producer / "etc/keybinding-producer.json").read_text())
        assert manifest["producer"] == MEDIA_NAME and manifest["targets"] == ["niri", "umbriel"]
        resources = [entry["path"] for entry in manifest["resources"]]
        assert len(resources) == 20
        assert len([path for path in resources if "/action/" in path]) == 10
        assert len([path for path in resources if "/keybinding/" in path]) == 10
        leaf = (producer / "bin/install-keybindings.sh").read_text()
        assert " install-offer " in leaf and "--selection" in leaf and "--registry-policy" in leaf
        assert "--profile" not in leaf
        assert json.loads((producer / "etc/keybindings/selection.json").read_text())["receivers"] is None
        for target in ["niri", "umbriel"]:
            assert not (producer / f"bin/install-keybindings-{target}.sh").exists()
        assert (producer / "bin/install.mjs").is_symlink()
        assert (producer / "bin/install-user.mjs").is_file() and not (producer / "bin/install-user.mjs").is_symlink()
        action_spec = json.loads((producer / "etc/compfuzor-actions/spec.json").read_text())
        assert action_spec["actions"]["install"]["plans"]["user"] == [{"kind": "action", "action": "install-keybindings"}]

        # Fresh roots; adoption first (consumer installers), then register.
        niri_home = area / "home-niri"
        umbriel_home = area / "home-umbriel"
        niri_env = consumer_env(niri_home)
        umbriel_env = consumer_env(umbriel_home)
        # Hosts publish their own descriptions; pure producer default-all needs
        # no baked-in profiles or fixture-specific receiver wiring.
        run([str(niri_host / "bin/install.mjs")], niri_env)
        run([str(umbriel_host / "bin/install.mjs")], umbriel_env)
        # Producer leaves directly (the proposal test's pattern): the
        # aggregate would run both targets against one environment.
        run([str(producer / "bin/install-keybindings.sh"), "--target", "niri"], niri_env)
        run([str(producer / "bin/install-keybindings.sh"), "--target", "umbriel"], umbriel_env)

        # Niri outcomes: fine-step Shift chords, coarse plain chords,
        # add-keys doubling, allow-when-locked, receiver links, includes.
        niri_dir = niri_home / ".config/niri"
        niri_generated = niri_home / ".config/niri/.keybindings/generated/niri"
        fine_up = (niri_generated / "media-volume-up-fine.binding.kdl").read_text()
        assert json.dumps("Shift+XF86AudioRaiseVolume") in fine_up and NIRI_FINE_UP in fine_up
        assert "allow-when-locked=true" in fine_up and "hotkey-overlay-title=\"Volume up (fine)\"" in fine_up
        coarse_up = (niri_generated / "media-volume-up.binding.kdl").read_text()
        assert json.dumps("XF86AudioRaiseVolume") in coarse_up and '"0.03+"' in coarse_up
        mute = (niri_generated / "media-mute.binding.kdl").read_text()
        assert json.dumps("XF86AudioMute") in mute and json.dumps("Shift+XF86AudioMute") in mute
        mic = (niri_generated / "media-mic-mute.binding.kdl").read_text()
        assert json.dumps("XF86AudioMicMute") in mic and "@DEFAULT_AUDIO_SOURCE@" in mic
        play = (niri_generated / "media-play-pause.binding.kdl").read_text()
        assert json.dumps("XF86AudioPlay") in play and 'spawn "playerctl" "play-pause";' in play
        for name in ["media-volume-up-fine", "media-volume-down-fine", "media-volume-up", "media-mute"]:
            assert (niri_dir / f"keybindings/{name}.binding.kdl").is_symlink()
            assert f"keybinding/niri/{name} start" in (niri_dir / "config.kdl").read_text()

        # Umbriel outcomes: same chords, shell-quoted spawn text, no
        # allow-when-locked leakage (niri-only option stays niri-only).
        umbriel_dir = umbriel_home / ".config/umbriel"
        umbriel_generated = umbriel_home / ".config/umbriel/.keybindings/generated/umbriel"
        fine_up_toml = (umbriel_generated / "media-volume-up-fine.binding.toml").read_text()
        assert json.dumps("Shift+XF86AudioRaiseVolume") in fine_up_toml and UMBRIEL_FINE_UP in fine_up_toml
        assert "allow-when-locked" not in fine_up_toml
        mute_toml = (umbriel_generated / "media-mute.binding.toml").read_text()
        assert json.dumps("XF86AudioMute") in mute_toml and json.dumps("Shift+XF86AudioMute") in mute_toml
        for name in ["media-volume-up-fine", "media-mute"]:
            assert (umbriel_dir / f"keybindings/{name}.binding.toml").is_symlink()
            assert f"keybinding/umbriel/{name} start" in (umbriel_dir / "config.toml").read_text()

        # Durable membership: exactly the media-keys producer group.
        for target, home in [("niri", niri_home), ("umbriel", umbriel_home)]:
            state = json.loads((home / f".config/{target}/.keybindings/membership.json").read_text())
            assert set(state["groups"]) == {MEDIA_NAME}

        # Native validation of both assembled roots when binaries exist.
        if subprocess.run(["sh", "-c", "command -v niri"], capture_output=True).returncode == 0:
            subprocess.run(["niri", "validate", "-c", str(niri_dir / "config.kdl")], env=niri_env, check=True, capture_output=True)
        if subprocess.run(["sh", "-c", "command -v umbriel"], capture_output=True).returncode == 0:
            subprocess.run(["umbriel", "validate", "-c", str(umbriel_dir / "config.toml")], env=umbriel_env, check=True, capture_output=True)
        print("ok: media-keys model producer — packaging, registration, chords, target policies, membership, native validation")


if __name__ == "__main__":
    test_media_keys_model_producer()
