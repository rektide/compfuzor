#!/usr/bin/env python3
"""Render real dial producer into scratch roots; no install or live effects."""
from __future__ import annotations

import hashlib
import difflib
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
    assert variables["KANATA_DIAL_PRECISION_STEP"] == "0.003"
    assert variables["SYSTEMD_ENABLE"] is False and variables["SYSTEMD_START"] is False
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
            "LINKS_BYPASS": False, "MODULES_BYPASS": True,
            "SYSTEMD_THUNK_BYPASS": True, "SYSTEMD_INSTALL_BYPASS": False,
            "ENV_BYPASS": True,
            "GET_URLS": [], "KANATA_DIAL_PRECISION_STEP": "0.004",
            "KANATA_DIAL_SYSTEM_ROOT": str(area / "system-runtime"),
        }
        spec = area / "scenario.json"
        spec.write_text(json.dumps(scenario))
        home = area / "home"
        home.mkdir()
        env = os.environ | {"HOME": str(home), "NODE_DISABLE_COMPILE_CACHE": "1"}
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
        assert (material / "kanata-dial/cli.ts").stat().st_mode & 0o777 == 0o644
        for name in ["protocol.ts", "relay.ts", "cli.ts"]:
            assert (material / "kanata-dial" / name).read_text().rstrip() == (ROOT / "files/kanata-dial" / name).read_text().rstrip()
        units = {p.name: p.read_text() for p in material.glob("*.service")}
        assert set(units) == {"kanata-dial-network.service", "kanata-dial.service", "kanata-dial-relay.service", "kanata-dial-reset.service"}
        assert "PrivateTmp=false" in units["kanata-dial-network.service"]
        for name in ["kanata-dial.service", "kanata-dial-relay.service", "kanata-dial-reset.service"]:
            assert "PrivateNetwork=True" in units[name]
            assert "JoinsNamespaceOf=kanata-dial-network.service" in units[name]
            assert "IPAddressDeny=any" in units[name] and "IPAddressAllow=127.0.0.1/32" in units[name]
            assert "RestrictAddressFamilies=AF_INET" in units[name]
            assert str(area / "system-runtime") in units[name]
            assert str(home) not in units[name] and str(material) not in units[name]
        assert "User=_kanata" in units["kanata-dial.service"] and "SupplementaryGroups=input" in units["kanata-dial.service"]
        assert "MemoryDenyWriteExecute=True" in units["kanata-dial.service"]
        for name in ["kanata-dial-relay.service", "kanata-dial-reset.service"]:
            assert "DynamicUser=True" in units[name] and "MemoryDenyWriteExecute=false" in units[name]
            assert "SupplementaryGroups" not in units[name] and "BindPaths" not in units[name]
            assert "ExecStart=/usr/bin/node " in units[name]
            assert "--jitless" not in units[name] and "expose-wasm" not in units[name]
        assert "ExecStopPost=/usr/bin/node " in units["kanata-dial-relay.service"]
        assert "ExecStopPost=" not in units["kanata-dial-reset.service"]
        assert not (area / "system-runtime").exists()
        plan = json.loads((material / "links.json").read_text())
        assets = [link for link in plan["links"] if str(area / "system-runtime") in link["dest"]]
        assert len(assets) == 4
        assert all(link["strategies"] == {"available": ["copy"], "default": "copy"} for link in assets)
        unit_links = [link for link in plan["links"] if "/etc/systemd/system/" in link["dest"]]
        assert len(unit_links) == 4 and all(link["strategies"]["default"] == "copy" for link in unit_links)
        # Exercise existing LINKS copy delivery ONLY for scratch runtime assets.
        # Unit destinations remain inert plan records and are never applied.
        runtime = area / "system-runtime"
        runtime.mkdir(mode=0o755)
        run("/usr/bin/node", "files/links/links.ts", "apply", str(material / "links.json"),
            "--scope", "system", "--id", ",".join(link["id"] for link in assets), "--sudo", "never", env=env)
        for asset in assets:
            copied = Path(asset["dest"])
            assert copied.is_file() and not copied.is_symlink()
            assert copied.stat().st_mode & 0o777 == 0o644
        run("/usr/bin/node", "--input-type=module", "-e", f"await import({json.dumps(str(runtime / 'cli.ts'))})", env=env)
        assert not list(home.rglob("membership.json"))
        assert not list(material.rglob("membership.json"))
        assert (material / "bin/install-system.mjs").exists()
        actions = json.loads((material / "compfuzor-actions/spec.json").read_text())
        assert "user" in actions["actions"]["install"]["plans"] and "system" in actions["actions"]["install"]["plans"]
        assert set(actions["actions"]["apply"]["plans"]) == {"user"}
        for installer in material.glob("bin/install-service-*.sh"):
            assert 'UNIT_ENABLE_TARGETS=""' in installer.read_text()
        # Optional main-owner integration: default body remains byte-exact;
        # enabled topology can retain live BlueTurn-only exclusion explicitly.
        main_material = area / "main-payload"
        main_scenario = scenario | {
            "DIR": str(main_material), "ETC": str(main_material), "BINS_DIR": str(main_material / "bin"),
            "KANATA_DIAL_ENABLED": False,
        }
        spec.write_text(json.dumps(main_scenario))
        run("ansible-playbook", "-i", "localhost,", "-c", "local", "kanata.srv.pb", "-e", f"@{spec}", env=env)
        default = (main_material / "kanata.kbd").read_bytes()
        expected = (ROOT / "tests/kanata-dial/fixtures/main-default.kbd").read_bytes()
        assert default == expected, "".join(difflib.unified_diff(expected.decode().splitlines(True), default.decode().splitlines(True)))
        main_unit = (main_material / "kanata.service").read_text()
        assert "--port" not in main_unit and "JoinsNamespaceOf" not in main_unit
        assert "IPAddressAllow" not in main_unit and "RestrictAddressFamilies=AF_AX25" in main_unit
        main_scenario |= {"KANATA_DIAL_ENABLED": True, "KANATA_DEV_NAMES_EXCLUDE": ["iRig BlueTurn Keyboard"]}
        spec.write_text(json.dumps(main_scenario))
        run("ansible-playbook", "-i", "localhost,", "-c", "local", "kanata.srv.pb", "-e", f"@{spec}", env=env)
        enabled = (main_material / "kanata.kbd").read_text()
        excludes = enabled.split("linux-dev-names-exclude (")[1].split(")")[0]
        assert '"Kinesis Freestyle Edge RGB Keyboard"' not in excludes
        assert '"iRig BlueTurn Keyboard"' in excludes
        assert '"Surface Dial Virtual Keyboard/Mouse"' in excludes and '"kanata-surface-dial"' in excludes
        assert "(deflayer dial-precision _ _ _)" in enabled and "(tap-hold 100 100 esc lctl)" in enabled
        assert ";; compfuzor kanata dial publisher enabled" in enabled
        run("/usr/local/bin/kanata", "--check", "--cfg", str(main_material / "kanata.kbd"))
        main_unit = (main_material / "kanata.service").read_text()
        assert "--port 127.0.0.1:5828" in main_unit and "JoinsNamespaceOf=kanata-dial-network.service" in main_unit
        assert "IPAddressDeny=any" in main_unit and "IPAddressAllow=127.0.0.1/32" in main_unit
        assert "MemoryDenyWriteExecute=True" in main_unit and "PrivateNetwork=True" in main_unit
        assert "RuntimeDirectory=kanata-dial-publisher" in main_unit and "BindsTo=kanata-dial-network.service" in main_unit
        run("/usr/bin/systemd-analyze", "verify", "--man=no",
            *(str(material / name) for name in units), str(main_material / "kanata.service"),
            env=env | {"SYSTEMD_UNIT_PATH": f"{material}:{main_material}:/usr/lib/systemd/system"})
        # Preserve leaves config bytes unchanged even if render options differ.
        (main_material / "kanata.kbd").write_bytes(default)
        main_scenario["KANATA_CONFIG_PRESERVE"] = True
        spec.write_text(json.dumps(main_scenario))
        run("ansible-playbook", "-i", "localhost,", "-c", "local", "kanata.srv.pb", "-e", f"@{spec}", env=env)
        assert (main_material / "kanata.kbd").read_bytes() == default
        assert (material / "bin/install-keybindings.sh").is_file()
        assert "install-offer" in (material / "bin/install-keybindings.sh").read_text()
        assert before == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    print("ok: isolated dial/main artifacts, copied scratch runtime, native TS, optional publisher, defaults/preserve unchanged, no live effects")


if __name__ == "__main__":
    main()
