#!/usr/bin/env python3
"""Real owner playbook declarations + committed artifact, isolated native CONFIG publications."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/registry-discovery/generated"

def run(command, env, check=True):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"failed {command}\n{result.stdout}\n{result.stderr}")
    return result

def render(directory, name, declarations, env):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "files").symlink_to(ROOT / "files", target_is_directory=True)
    payload = directory / "deployment"
    variables = {"TYPE": name, "NAME": name, "DIR": str(payload), "ETC": str(payload), "BINS_DIR": str(payload / "bin"),
        "DIRSET": ["etc"], "FILES": [], "ETC_FILES": [], "BINS": [], "DIRS": [], "STATUSES": [], "PKGS": [], "ENV": {}, "BINS_RUN_BYPASS": True,
        "ACTION_AUDIENCES": {"default": "user"}, **declarations}
    tasks = [{"set_fact": {"SUBSYSTEM": {}}}]
    for task in ["sub_attribution", "sub_config", "gen_keybindings", "gen_config", "gen_bins", "gen_attribution", "compile_artifacts"]:
        tasks.append({"import_tasks": str(ROOT / f"tasks/compfuzor/{task}.tasks")})
    tasks += [{"file": {"path": str(payload), "state": "directory"}}, {"import_tasks": str(ROOT / "tasks/compfuzor/fs_hierarchy.tasks"), "vars": {"include": "etc"}},
        {"file": {"path": "{{item}}", "state": "directory"}, "loop": "{{DIRS}}"}, {"import_tasks": str(ROOT / "tasks/compfuzor/bins.tasks")},
        {"import_tasks": str(ROOT / "tasks/compfuzor/bins_link.tasks")}]
    pb = directory / "render.pb"
    pb.write_text(yaml.safe_dump([{"hosts": "all", "gather_facts": False, "vars_files": [str(ROOT / "vars/common.yaml")], "vars": variables, "tasks": tasks}], sort_keys=False))
    run(["ansible-playbook", "-i", "localhost,", "-c", "local", str(pb), "-e", json.dumps({"TYPE": name, "NAME": name})], env)
    return payload

def playbook(name):
    raw = yaml.safe_load((ROOT / name).read_text())[0]["vars"]
    return {key: value for key, value in raw.items() if key in ("KEYBINDING_ACTIONS", "KEYBINDINGS", "KEYBINDING_CONSUMERS", "ETC_FILES", "BINS", "ACTION_AUDIENCES", "UMBRIEL_MIGRATIONS")}

def test_generated():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "README.md").write_text("# Generated rendezvous/native proof\nActual owner declarations, committed bundled runtime and isolated HOME/XDG/native CONFIG outputs. Only this script's own proof tree is removed.\n")
    with tempfile.TemporaryDirectory(prefix="proof-", dir=SCRATCH) as temporary:
        area = Path(temporary)
        env = {**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"), "HOME": str(area / "home"), "XDG_CONFIG_HOME": str(area / "config"),
            "XDG_DATA_HOME": str(area / "data"), "XDG_DATA_DIRS": str(area / "vendor"), "XDG_CONFIG_DIRS": str(area / "site"),
            "XDG_STATE_HOME": str(area / "state"), "XDG_CACHE_HOME": str(area / "cache"), "TMPDIR": str(SCRATCH)}
        node = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()
        env["PATH"] = os.pathsep.join([str(Path(node).parent), "/usr/local/bin", "/usr/bin", "/bin", str(Path.home() / ".local/share/pnpm")])
        for key in ["DIR", "NAME", "COMPFUZOR_NIRI_PROFILE", "COMPFUZOR_UMBRIEL_PROFILE", "COMPFUZOR_CONFIG_BYPASS", "COMPFUZOR_KEYBINDINGS_BYPASS"]:
            env.pop(key, None)
        niri = render(area / "niri", "niri", playbook("niri.etc.pb"), env)
        umbriel = render(area / "umbriel", "umbriel", playbook("umbriel.etc.pb"), env)
        deck = render(area / "deck", "deck", {"KEYBINDING_CONSUMERS": {"deck-main": {"adapter": "niri", "contexts": {"user": {"scope": "user", "root": "config", "subpath": "deck-main"}}, "baseline": []}}}, env)
        media = render(area / "media", "media-keys-main", playbook("media-keys.etc.pb"), env)
        rendezvous = area / "data/compfuzor/keybindings/consumers.d"
        assert not rendezvous.exists(), "render must not register or discover controller HOME"
        # Passive publication works before native install; descriptions are still owner-held.
        for host, id in [(niri, "niri"), (umbriel, "umbriel"), (deck, "deck-main")]:
            run([str(host / f"bin/register-keybindings-consumer-{id}-user.sh")], env)
            assert (rendezvous / f"{id}.json").resolve() == (host / f"etc/keybindings/consumers/user/{id}.json").resolve()
            run([str(host / "bin/install.mjs")], env)
        assert not (media / "bin/install-keybindings-niri.sh").exists()
        run([str(media / "bin/install.mjs")], env)
        providers = area / "data/compfuzor/keybindings/providers.d"
        assert (providers / "media-keys-main.json").resolve() == (media / "etc/keybinding-producer.json").resolve()
        states = {id: area / f"config/{id}/.keybindings/membership.json" for id in ["niri", "umbriel", "deck-main"]}
        for id, state in states.items():
            assert "media-keys-main" in json.loads(state.read_text())["groups"], id
        # Same native adapter, different receiver identity/root.
        assert json.loads((deck / "etc/keybinding-deck-main.json").read_text())["target"] == "niri"
        link = rendezvous / "niri.json"
        link.rename(str(link) + ".disabled")
        roots_before = {id: state.read_bytes() for id, state in states.items()}
        rejected = run([str(media / "bin/install.mjs"), "--target", "niri"], env, False)
        assert rejected.returncode and "--force-enable" in rejected.stderr
        assert all(state.read_bytes() == roots_before[id] for id, state in states.items())
        run([str(media / "bin/install.mjs"), "--force-enable", "--target", "niri"], env)
        assert Path(str(link) + ".disabled").is_symlink() and not link.exists()
        # Receiver force must not undo the consumer-owned producer group's disable.
        run([str(niri / "bin/keybindings.mjs"), "disable", "--target", "niri", "--profile", str(niri / "etc/keybinding-niri.json"), "--context", "user", "--scope", "user", "--group", "media-keys-main"], env)
        run([str(media / "bin/install.mjs"), "--force-enable"], env)
        assert json.loads(states["niri"].read_text())["groups"]["media-keys-main"]["enabled"] is False
        masks = area / "config/compfuzor/keybindings/consumers.mask.d"
        masks.mkdir(parents=True)
        (masks / "umbriel.json").symlink_to("/dev/null")
        # Passive publication is still current under a higher mask.
        run([str(umbriel / "bin/register-keybindings-consumer-umbriel-user.sh")], env)
        rejected = run([str(media / "bin/install.mjs"), "--force-enable", "--target", "umbriel"], env, False)
        assert rejected.returncode and "masked" in rejected.stderr
        assert (masks / "umbriel.json").readlink() == Path("/dev/null")
        # A newly prospective host can install before its advertisement exists.
        (rendezvous / "deck-main.json").unlink()
        run([str(deck / "bin/install.mjs")], env)
        assert (rendezvous / "deck-main.json").is_symlink()
        print("ok: actual media-keys + Niri/Umbriel ownership, named receiver, bundled generated registration, CONFIG commits, disabled force and mask veto")

if __name__ == "__main__":
    test_generated()
