#!/usr/bin/env python3
"""Render real dial producer into scratch roots; no install or live effects."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/kanata-dial"


def run(*args: str, env: dict | None = None) -> str:
    result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"{args}:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def main() -> None:
    protected = [ROOT / name for name in ("media-keys.etc.pb", "kanata.srv.pb", "kinata.srv.pb", "kanata-blueturn.srv.pb")]
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    variables = yaml.safe_load((ROOT / "kanata-dial.etc.pb").read_text())[0]["vars"]
    assert variables["KEYBINDING_PRODUCER"] == "kanata-dial"
    assert variables["KEYBINDING_ORDER"] == 110
    assert not any(key.startswith("SYSTEMD_") for key in variables)
    assert "LINKS" not in variables
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="render-", dir=SCRATCH) as directory:
        area = Path(directory)
        material = area / "payload"
        scenario = {
            "DIR": str(material), "ETC": str(material),
            "PREFIX_DIR": str(area), "BINS_DIR": str(material / "bin"),
            "SRVS_DIR": str(area / "srv"), "ETCS_DIR": str(area / "etc-opt"),
            "REPO_BYPASS": True, "PKGS_BYPASS": True, "APT_BYPASS": True,
            "ARCH_BYPASS": True, "BINS_RUN_BYPASS": True, "GLOBAL_BINS_BYPASS": True,
            "LINKS_BYPASS": True, "MODULES_BYPASS": True,
            "SYSTEMD_THUNK_BYPASS": True, "SYSTEMD_INSTALL_BYPASS": True,
            "ENV_BYPASS": True,
            "GET_URLS": [], "KANATA_DIAL_PRECISION_STEP": "0.004",
        }
        spec = area / "scenario.json"
        spec.write_text(json.dumps(scenario))
        home = area / "home"
        home.mkdir()
        env = os.environ | {"HOME": str(home)}
        run("ansible-playbook", "-i", "localhost,", "-c", "local", "kanata-dial.etc.pb", "-e", f"@{spec}", env=env)
        manifest = json.loads((material / "keybinding-producer.json").read_text())
        assert manifest["producer"] == "kanata-dial" and manifest["order"] == 110
        assert manifest["targets"] == ["niri", "umbriel"]
        assert len(manifest["resources"]) == 4
        for direction, code, suffix in [("up", "F23", "+"), ("down", "F24", "-")]:
            binding = yaml.safe_load((material / f"keybinding/kanata-dial-volume-{direction}-precision.yaml").read_text())
            action = yaml.safe_load((material / f"action/kanata-dial-volume-{direction}-precision.yaml").read_text())
            assert binding["keys"] == [code] and binding["add-keys"] == [f"Shift+{code}"]
            assert f"0.004{suffix}" in action["exec"]
        for name in ["dial.kbd", "keyboard-signal.example.kbd"]:
            run("/usr/local/bin/kanata", "--check", "--cfg", str(material / "kanata-dial" / name))
        assert (material / "kanata-dial/cli.ts").stat().st_mode & 0o111
        for name in ["protocol.ts", "relay.ts", "cli.ts"]:
            assert (material / "kanata-dial" / name).read_text().rstrip() == (ROOT / "files/kanata-dial" / name).read_text().rstrip()
        assert not list(material.rglob("*.service"))
        assert not list(home.rglob("membership.json"))
        assert not list(material.rglob("membership.json"))
        assert not (material / "bin/install-system.mjs").exists()
        assert (material / "bin/install-keybindings.sh").is_file()
        assert "install-offer" in (material / "bin/install-keybindings.sh").read_text()
        assert before == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    print("ok: isolated dial render, separate membership, configurable amount, parser checks, no unit/install effects")


if __name__ == "__main__":
    main()
