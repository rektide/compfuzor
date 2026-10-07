#!/usr/bin/env python3
"""Bounded real combined first-install and public SYSTEM policy-pair proof."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("registry_generated", ROOT / "tests/integration/registry_keybindings_generated.test.py")
proof = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proof)

def test_combined():
    scratch = ROOT / ".test-agent/registry-discovery/combined"
    scratch.mkdir(parents=True, exist_ok=True)
    (scratch / "README.md").write_text("# Combined prospective/policy proof\nReal generated combined native workloads and explicit isolated USER/SYSTEM registry policy pairs. No live registries/native outputs.\n")
    with tempfile.TemporaryDirectory(prefix="proof-", dir=scratch) as temporary:
        area = Path(temporary)
        node = proof.run(["node", "-p", "process.execPath"], os.environ).stdout.strip()
        env = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "HOME": str(area / "home"), "XDG_CONFIG_HOME": str(area / "config"), "XDG_DATA_HOME": str(area / "unused-data"), "XDG_CONFIG_DIRS": str(area / "unused-config-dirs"), "XDG_DATA_DIRS": str(area / "unused-data-dirs"), "TMPDIR": str(scratch), "TRACE": str(area / "trace")}
        env["PATH"] = os.pathsep.join([str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin", str(Path.home() / ".local/share/pnpm")])
        for key in ["DIR", "NAME", "COMPFUZOR_NIRI_PROFILE", "COMPFUZOR_UMBRIEL_PROFILE", "COMPFUZOR_KEYBINDINGS_BYPASS", "COMPFUZOR_CONFIG_BYPASS"]: env.pop(key, None)
        def side(audience, role):
            root = "${HOME}/registries/" + audience + "/" + role + ".d"
            return {"roots": [root], "writeRoot": root}
        policy = {"version": 1, "audiences": {audience: {role: side(audience, role) for role in ["providers", "consumers"]} for audience in ["user", "system"]}}
        declarations = {
            "KEYBINDING_ACTIONS": {"launch": {"exec": ["echo", "combined"]}},
            "KEYBINDINGS": {"launch": {"action": "launch", "keys": ["Mod+D"]}},
            "KEYBINDING_CONSUMERS": {"niri": {"contexts": {"user": {"scope": "user", "root": str(area / "native-user")}, "host": {"scope": "system", "root": str(area / "native-system")}}, "action_contexts": {"user": "user", "system": "host"}, "baseline": [], "registration": "copy"}},
            "KEYBINDING_TARGETS": {"niri": {"action_contexts": {"user": "user", "system": "host"}}, "only-system": {"scope": "system"}},
            "KEYBINDING_REGISTRY_POLICY": policy,
            "BINS": [{"name": "install-user.sh", "deployment_rooted": True, "content": 'printf "user-body\\n" >> "$TRACE"\nif [ "${FIRST_INSTALL:-}" = 1 ]; then test ! -e "$HOME/registries/user/consumers.d/niri.json"; fi\n'}, {"name": "install.sh", "deployment_rooted": True, "content": 'printf "system-body\\n" >> "$TRACE"\nif [ "${FIRST_INSTALL:-}" = 1 ]; then test ! -e "$HOME/registries/system/consumers.d/niri.json"; fi\n'}],
        }
        # The other-audience ID must not be looked up in USER scope. For SYSTEM
        # explicitly narrow to niri, rather than requesting an absent unrelated ID.
        deployment = proof.render(area / "owner", "combined", declarations, env)
        user_link = area / "home/registries/user/consumers.d/niri.json"
        assert not user_link.exists()
        first = proof.run([str(deployment / "bin/install.mjs")], {**env, "FIRST_INSTALL": "1"})
        assert "user-body" in (area / "trace").read_text()
        assert user_link.is_symlink()
        membership = area / "native-user/.keybindings/membership.json"
        assert json.loads(membership.read_text())["groups"]["combined"]["resources"]
        assert "combined" in (area / "native-user/config.kdl").read_text()
        proof.run([str(deployment / "bin/install.mjs"), "--target", "niri"], env)
        # Only a selected producer batch gives --target receiver-subset meaning.
        # A focused owned-host assembly must reject a different native adapter.
        before_root = (area / "native-user/config.kdl").read_bytes()
        rejected = proof.run([str(deployment / "bin/assemble-keybindings-niri.mjs"), "--target", "umbriel"], env, False)
        assert rejected.returncode and "adapter mismatch" in rejected.stderr
        assert (area / "native-user/config.kdl").read_bytes() == before_root
        proof.run([str(deployment / "bin/install-system.mjs"), "--target", "niri"], {**env, "FIRST_INSTALL": "1"})
        assert (area / "home/registries/system/consumers.d/niri.json").is_symlink()
        assert (area / "home/registries/system/providers.d/combined.json").is_symlink()
        assert json.loads((area / "native-system/.keybindings/membership.json").read_text())["groups"]["combined"]["resources"]
        assert not (area / "unused-data/compfuzor").exists(), "supplied pair must not fall back to default XDG registry"
        # Host bootstrap reads accepted copied sources; a later producer native
        # rejection restores its candidate registration and leaves membership/root.
        action = deployment / "etc/action/launch.yaml"
        original = action.read_bytes()
        invalid = yaml.safe_load(original); invalid["niri"] = {"native": {"name": "invented-invalid-action"}}
        old_state = membership.read_bytes(); native_root = area / "native-user/config.kdl"; old_root = native_root.read_bytes()
        managed = area / "native-user/.keybindings/source/combined/action/launch.yaml"; old_managed = managed.read_bytes()
        action.write_text(yaml.safe_dump(invalid))
        rejected = proof.run([str(deployment / "bin/install.mjs"), "--target", "niri"], env, False)
        assert rejected.returncode and membership.read_bytes() == old_state and native_root.read_bytes() == old_root and managed.read_bytes() == old_managed
        action.write_bytes(original)
        # New unexpected publication/control must abort before the authored body.
        before_trace = (area / "trace").read_bytes()
        user_link.unlink(); user_link.symlink_to("/dev/null")
        rejected = proof.run([str(deployment / "bin/install.mjs"), "--force-enable"], env, False)
        assert rejected.returncode and (area / "trace").read_bytes() == before_trace
        assert "masked" in rejected.stderr or "publication blocked" in rejected.stderr
        print("ok: real combined prospective first-install/reinstall/subset, host-before-producer, public isolated SYSTEM pair and pre-body mask veto")

if __name__ == "__main__":
    test_combined()
