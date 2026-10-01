#!/usr/bin/env python3
"""Real generated producer installers over stock CONFIG artifacts; isolated users."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/keybindings-generated"

def run(command, env, check=True):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"failed {command}\n{result.stdout}\n{result.stderr}")
    return result

def render(directory, name, declarations, env):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "files").symlink_to(ROOT / "files", target_is_directory=True) if not (directory / "files").exists() else None
    payload = directory / "deployment"
    variables = {"TYPE": name, "NAME": name, "DIR": str(payload), "ETC": str(payload / "etc"), "BINS_DIR": str(payload / "bin"), "DIRSET": ["etc"], "FILES": [], "ETC_FILES": [], "BINS": [{"name": "install.sh", "content": "printf 'authored-system-body\\n'\n"}, {"name": "install-user.sh", "content": "printf 'authored-user-body\\n'\n"}], "DIRS": [], "STATUSES": [], "PKGS": [], "ENV": {}, "BINS_RUN_BYPASS": True, **declarations}
    tasks = [{"set_fact": {"SUBSYSTEM": {}}}]
    for task in ["sub_attribution", "sub_config", "gen_keybindings", "gen_config", "gen_bins", "gen_attribution", "compile_artifacts"]:
        tasks.append({"import_tasks": str(ROOT / f"tasks/compfuzor/{task}.tasks")})
    tasks += [{"file": {"path": str(payload), "state": "directory"}}, {"import_tasks": str(ROOT / "tasks/compfuzor/fs_hierarchy.tasks"), "vars": {"include": "etc"}}, {"file": {"path": "{{item}}", "state": "directory"}, "loop": "{{DIRS}}"}, {"import_tasks": str(ROOT / "tasks/compfuzor/bins.tasks")}, {"import_tasks": str(ROOT / "tasks/compfuzor/bins_link.tasks")}, {"copy": {"dest": str(directory / "plan.json"), "content": "{{ {'bins': BINS} | to_nice_json }}"}}]
    playbook = directory / "render.pb"
    playbook.write_text(yaml.safe_dump([{"hosts": "all", "gather_facts": False, "vars_files": [str(ROOT / "vars/common.yaml")], "vars": variables, "tasks": tasks}], sort_keys=False))
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", json.dumps({"TYPE": name, "NAME": name})], env)
    plan = json.loads((directory / "plan.json").read_text())
    for target in ["niri", "umbriel"]:
        members = [item for item in plan["bins"] if item.get("name") == f"install-keybindings-{target}.sh"]
        assert len(members) == 1 and members[0]["scope"] == ["user"] and members[0]["run"] is False
        assert sum(Path(name).name == f"install-keybindings-{target}.sh" for item in plan["bins"] for name in item.get("run_all", [])) == 1
    assert "authored-system-body" in (payload / "bin/install.sh").read_text()
    assert "install-keybindings-niri.sh" not in (payload / "bin/install.sh").read_text()
    assert (payload / "bin/config/run.sh").read_bytes() == (ROOT / "files/config-run.sh").read_bytes()
    assert (payload / "bin/config/processors/concat").is_file()
    return payload

def test_generated():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text("# Generated installer scratch\nReal Ansible artifacts and isolated HOME/XDG consumers; no live configs.\n")
    with tempfile.TemporaryDirectory(prefix="proof-", dir=SCRATCH) as tmp:
        area = Path(tmp)
        home = area / "home"
        config = home / ".config"
        env = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "HOME": str(home), "XDG_CONFIG_HOME": str(config), "TMPDIR": str(SCRATCH)}
        node = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()
        env["PATH"] = os.pathsep.join([str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin", str(Path.home() / ".local/share/pnpm")])
        for variable in ["DIR", "NAME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "COMPFUZOR_CONFIG_BYPASS", "COMPFUZOR_KEYBINDINGS_BYPASS"]:
            env.pop(variable, None)
        consumers = {}
        for target, ext in [("niri", "kdl"), ("umbriel", "toml")]:
            user = config / target
            user.mkdir(parents=True)
            native = lambda key, text: f'binds {{ {key} {{ spawn "echo" "{text}"; }}; }}\n' if target == "niri" else f'[keybinds]\n"{key}" = "spawn:echo {text}"\n'
            baseline = area / f"baseline-{target}.{ext}"
            baseline.write_text(native("Mod+B", "baseline"))
            (user / f"personal.{ext}").write_text(native("Mod+P", "personal"))
            (user / f"own.{ext}").write_text(native("Mod+U", "own"))
            consumers[target] = {"contexts": {"user": {"scope": "user", "root": "config", "subpath": target}}, "baseline": [str(baseline)], "personal": [f"personal.{ext}"], "placement": "copy" if target == "niri" else "link", "registration": "copy" if target == "niri" else "link", "native_sources": [{"id": "own", "path": f"own.{ext}", "order": 9000}]}
        host = render(area / "host", "desktop", {"KEYBINDING_CONSUMERS": consumers, "KEYBINDINGS": {"alpha-launch": {"patch": True, "niri": {"keys": ["Alt+D"]}}}}, env)
        targets = {target: {"consumer": str(host), "context": "user", "scope": "user"} for target in ["niri", "umbriel"]}
        alpha = {"KEYBINDING_ACTIONS": {"alpha-run": {"exec": ["echo", "alpha-first"]}}, "KEYBINDINGS": {"alpha-launch": {"action": "alpha-run", "keys": ["Mod+D"], "umbriel": {"keys": ["Mod+Space"]}}, "alpha-extra": {"action": "alpha-run", "keys": ["Alt+Grave"], "umbriel": {"keys": ["Mod+Grave"]}}}, "KEYBINDING_TARGETS": targets}
        beta = {"KEYBINDING_ACTIONS": {"beta-run": {"exec": ["echo", "beta-first"]}}, "KEYBINDINGS": {"beta-launch": {"action": "beta-run", "keys": ["Mod+F"], "umbriel": {"keys": ["Mod+Slash"]}}}, "KEYBINDING_TARGETS": targets}
        first = render(area / "alpha", "alpha", alpha, env)
        second = render(area / "beta", "beta", beta, env)
        assert not (config / "niri/config.kdl").exists() # Render does not install.
        # Consumer own patch is dormant before the producer exists.
        run([str(host / "bin/install-user.sh")], env)
        installed = run([str(first / "bin/install-user.sh")], env)
        assert installed.stdout.count("authored-user-body\n") == 1
        run([str(second / "bin/install-user.sh")], env)
        states = {target: config / target / ".keybindings/membership.json" for target in ["niri", "umbriel"]}
        roots = {"niri": config / "niri/config.kdl", "umbriel": config / "umbriel/config.toml"}
        for target in states:
            state = json.loads(states[target].read_text())
            assert set(state["groups"]) == {"alpha", "beta"}
            assert roots[target].read_text().count(f"keybinding/{target}/alpha-launch start") == 1
            assert "own." in roots[target].read_text() and "personal." in roots[target].read_text()
        niri_copy = config / "niri/keybindings/alpha-launch.binding.kdl"
        assert '"Alt+D"' in niri_copy.read_text()
        assert (config / "umbriel/keybindings/alpha-launch.binding.toml").is_symlink()
        assert '"Mod+Space"' in (config / "umbriel/keybindings/alpha-launch.binding.toml").read_text()
        niri_copy.write_text('binds { Alt+D { spawn "echo" "user-edited"; }; }\n')
        alpha["KEYBINDING_ACTIONS"]["alpha-run"]["exec"] = ["echo", "alpha-second"]
        alpha["KEYBINDINGS"].pop("alpha-extra")
        first = render(area / "alpha", "alpha", alpha, env)
        run([str(first / "bin/install-user.sh")], env)
        assert "user-edited" in niri_copy.read_text()
        assert "alpha-second" in (config / "umbriel/keybindings/alpha-launch.binding.toml").read_text()
        assert '"Alt+D"' in (config / "niri/.keybindings/generated/niri/alpha-launch.binding.kdl").read_text()
        for target in states:
            group = json.loads(states[target].read_text())["groups"]["alpha"]
            assert {resource["id"] for resource in group["resources"]} == {"alpha-run", "alpha-launch"}
            assert "alpha-extra start" not in roots[target].read_text()
            assert (config / target / ".keybindings/source/alpha/keybinding/alpha-extra.yaml").exists() # Excluded, not pruned.
        # Invalid reinstall cannot accept membership or copied YAML registration.
        old_state = states["niri"].read_bytes()
        old_root = roots["niri"].read_bytes()
        old_decl = (config / "niri/.keybindings/source/beta/action/beta-run.yaml").read_bytes()
        beta["KEYBINDING_ACTIONS"]["beta-run"] = {"niri": {"native": {"name": "invented-invalid-action"}}, "umbriel": {"native": "invented-invalid-action"}}
        second = render(area / "beta", "beta", beta, env)
        rejected = run([str(second / "bin/install-user.sh")], env, check=False)
        assert rejected.returncode != 0 and states["niri"].read_bytes() == old_state and roots["niri"].read_bytes() == old_root
        assert (config / "niri/.keybindings/source/beta/action/beta-run.yaml").read_bytes() == old_decl
        beta["KEYBINDING_ACTIONS"]["beta-run"] = {"exec": ["echo", "beta-first"]}
        render(area / "beta", "beta", beta, env)
        # Contribution disabling is durable; reinstall preserves it and the user overlay.
        for target in states:
            run([str(host / "bin/keybindings.mjs"), "disable", "--profile", str(host / f"etc/keybinding-{target}.json"), "--target", target, "--context", "user", "--scope", "user", "--group", "alpha"], env)
            assert "alpha-launch start" not in roots[target].read_text()
            assert "beta-launch start" in roots[target].read_text()
        run([str(first / "bin/install-user.sh")], env)
        assert all(json.loads(path.read_text())["groups"]["alpha"]["enabled"] is False for path in states.values())
        for target in states:
            active = config / target / ".keybindings/source/beta/keybinding/beta-launch.yaml"
            active.rename(str(active) + ".disabled")
        run([str(second / "bin/install-user.sh")], env)
        for target in states:
            active = config / target / ".keybindings/source/beta/keybinding/beta-launch.yaml"
            assert not active.exists() and Path(str(active) + ".disabled").exists()
            assert "beta-launch start" not in roots[target].read_text()
        print("ok: generated stock workers/install aggregation, two producers, overlays/native, source/material policies, smaller membership, rollback and durable disable")

if __name__ == "__main__":
    test_generated()
