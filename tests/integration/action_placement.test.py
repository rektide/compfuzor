#!/usr/bin/env python3
"""Real home-local defaults without DIR/ETC overrides; no live receivers or services."""
from __future__ import annotations
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/action-placement"
spec = importlib.util.spec_from_file_location("consumer_hosts", ROOT / "tests/integration/keybindings_consumer_hosts.test.py")
hosts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hosts)
MEDIA_VARS = yaml.safe_load((ROOT / "media-keys.etc.pb").read_text())[0]["vars"]
MEDIA_NAME = MEDIA_VARS.get("NAME", MEDIA_VARS["TYPE"] + ("-" + MEDIA_VARS["INSTANCE"] if MEDIA_VARS.get("INSTANCE") else ""))


def environment(area: Path) -> dict:
    env = hosts.consumer_env(area / "home")
    env.update({"XDG_DATA_HOME": str(area / "data"), "XDG_CONFIG_HOME": str(area / "receivers"), "XDG_CACHE_HOME": str(area / "cache"), "XDG_STATE_HOME": str(area / "state"), "TMPDIR": str(SCRATCH), "ANSIBLE_LOCAL_TEMP": str(area / "ansible-local"), "ANSIBLE_REMOTE_TEMP": str(area / "ansible-remote")})
    for key in ["COMPFUZOR_NIRI_PROFILE", "COMPFUZOR_UMBRIEL_PROFILE", "COMPFUZOR_ACTION_SESSION", "COMPFUZOR_ACTION_OPERATION", "COMPFUZOR_ACTION_OPERATION_MODE"]:
        env.pop(key, None)
    return env


def render(playbook: str, area: Path, env: dict, extra: dict | None = None) -> tuple[Path, dict]:
    area.mkdir(parents=True, exist_ok=True)
    report = area / "report.json"
    wrapper = area / "render.etc.pb"
    wrapper.write_text(yaml.safe_dump([
        {"import_playbook": str(ROOT / playbook)},
        {"hosts": "all", "gather_facts": False, "tasks": [{"copy": {"dest": str(report), "content": "{{ {'dir': DIR, 'prefix': PREFIX_DIR, 'etc': _ARTIFACTS.families.ETC_FILES.materialized_root, 'bins': DIR ~ '/bin', 'name': DIR | basename, 'dirs': DIRS, 'artifacts': _ARTIFACTS} | to_nice_json }}"}}]},
    ], sort_keys=False))
    # No DIR/ETC/BINS_DIR/PREFIX_DIR placement override in the default proof.
    scenario = {"REPO_BYPASS": True, "GIT_BYPASS": True, "PKGS_BYPASS": True, "APT_BYPASS": True, "ARCH_BYPASS": True, "MODULES_BYPASS": True, "BINS_RUN_BYPASS": True, "GLOBAL_BINS_BYPASS": True, "LINKS_BYPASS": True, "SYSTEMD_THUNK_BYPASS": True, "GET_URLS": []}
    if extra:
        scenario.update(extra)
    scenario_file = area / "scenario.json"
    scenario_file.write_text(json.dumps(scenario))
    result = subprocess.run([shutil.which("ansible-playbook"), "-i", "localhost,", "-c", "local", str(wrapper), "-e", "@" + str(scenario_file)], cwd=ROOT, env={**env, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(report.read_text())
    return Path(payload["dir"]), payload


def destinations(value):
    if isinstance(value, dict):
        if "resolved_dest" in value:
            yield Path(value["resolved_dest"])
        for child in value.values():
            yield from destinations(child)
    elif isinstance(value, list):
        for child in value:
            yield from destinations(child)


def invoke(path: Path, env: dict, args=(), expected=0):
    result = subprocess.run([str(path), *args], cwd=ROOT, env=env, text=True, capture_output=True)
    assert result.returncode == expected, result.stdout + result.stderr
    return result


def test_home_defaults(area: Path):
    env = environment(area)
    material = Path(env["XDG_DATA_HOME"]) / "compfuzor/etc"
    baseline = Path("/usr/local/share/umbriel/config.toml")
    assert baseline.is_file(), "real Umbriel host validation requires its separately installed read-only baseline"
    template = (ROOT / "files/umbriel/config.toml").read_text()
    umbrella_inputs = {}
    deployed = {}
    for name, filename, extra in [("niri", "niri.etc.pb", None), ("umbriel", "umbriel.etc.pb", umbrella_inputs), (MEDIA_NAME, "media-keys.etc.pb", None)]:
        directory, report = render(filename, area / (name + "-render"), env, extra)
        assert directory == material / name, report
        assert Path(report["prefix"]) == material
        assert Path(report["etc"]) == directory and Path(report["bins"]) == directory / "bin"
        assert (directory / "etc").is_symlink() and (directory / "etc").resolve() == directory.resolve()
        assert all(path.is_relative_to(directory) for path in destinations(report["artifacts"])), report["artifacts"]
        assert all(Path(path).is_relative_to(directory) for path in report["dirs"]), report["dirs"]
        assert (directory / "bin/install.mjs").is_symlink()
        assert not (directory / "bin/install-system.mjs").exists()
        deployed[name] = directory
    assert not Path(env["XDG_CONFIG_HOME"]).exists(), "generation must not install receiver configuration"
    # Existing fs_env exposes sibling env.NAME links under the same material group.
    assert all(path.is_relative_to(material) for path in material.rglob("*"))
    assert all(path.resolve().is_relative_to(material.resolve()) for path in material.iterdir() if path.is_symlink())
    niri, umbriel, producer = deployed["niri"], deployed["umbriel"], deployed[MEDIA_NAME]
    assert (umbriel / "config.toml").read_text() == template
    for target, host in [("niri", niri), ("umbriel", umbriel)]:
        invoke(host / "bin/install.mjs", env)
        assert (host / "bin/assemble.mjs").is_symlink() and not (host / "bin/assemble-system.mjs").exists()
    receiver = Path(env["XDG_CONFIG_HOME"])
    assert (receiver / "umbriel/config.toml").is_file() and not (receiver / "umbriel/config.toml").is_symlink()
    assert (receiver / "umbriel/config.toml").resolve() != (umbriel / "config.toml").resolve()
    assert not (umbriel / ".keybindings").exists(), "material root is not the live receiver"
    for target in ["niri", "umbriel"]:
        wrapper = (producer / f"bin/install-keybindings-{target}.sh").read_text()
        assert "--profile-selector" in wrapper and "${XDG_DATA_HOME}" in wrapper
        assert env["HOME"] not in wrapper and "/etc/opt/" not in wrapper
    invoke(producer / "bin/install.mjs", env)
    assert (umbriel / "config.toml").read_text() == template, "native publication must not rewrite the staged template"
    assert (receiver / "umbriel/config.toml").read_text() != template
    for target, host in [("niri", niri), ("umbriel", umbriel)]:
        state = json.loads((receiver / target / ".keybindings/membership.json").read_text())
        assert set(state["groups"]) == {MEDIA_NAME} and len(state["groups"][MEDIA_NAME]["resources"]) == 20
        invoke(host / "bin/assemble.mjs", env, ["--check"])
        invoke(host / "bin/assemble.mjs", env)
    assert not (producer / "bin/assemble.mjs").exists(), "producer is not a fabricated host assembler"
    service_calls = Path(env["SERVICE_TEST_TRACE"]).read_text().splitlines() if Path(env["SERVICE_TEST_TRACE"]).exists() else []
    assert all(call == "--version" for call in service_calls), service_calls  # renderer probes only; the manager is stubbed
    print("ok: real default HOME/XDG placement, structural etc exposure, full user action and both native targets")
    return env, deployed, umbrella_inputs


def test_system_fixture_and_shared(area: Path, env: dict, deployed: dict, umbrella_inputs: dict):
    system = area / "system-receiver/niri"
    contexts = {"user": {"scope": "user", "root": "config", "subpath": "niri"}, "host": {"scope": "system", "root": str(system)}}
    directory, _ = render("niri.etc.pb", area / "niri-both-render", env, {"KEYBINDING_CONSUMERS": {"niri": {"contexts": contexts}}})
    assert directory == deployed["niri"], "both scopes must use the same home-local material"
    invoke(directory / "bin/install-system.mjs", env)
    assert (system / "config.kdl").is_file()
    invoke(directory / "bin/assemble-system.mjs", env, ["--check"])
    targets = {"niri": {"consumer": {"env": "COMPFUZOR_NIRI_PROFILE", "default": "${XDG_DATA_HOME}/compfuzor/etc/niri/etc/keybinding-niri.json"}, "context": "user", "scope": "user", "action_contexts": {"user": "user", "system": "host"}}}
    producer, _ = render("media-keys.etc.pb", area / "media-both-render", env, {"KEYBINDING_TARGETS": targets})
    invoke(producer / "bin/install-system.mjs", env)
    assert json.loads((system / ".keybindings/membership.json").read_text())["groups"][MEDIA_NAME]["resources"]
    shared = area / "shared-material/etc"
    shared_host, report = render("niri.etc.pb", area / "niri-shared-render", env, {"PREFIX_DIR": str(shared), "KEYBINDING_CONSUMERS": {"niri": {"contexts": {"user": contexts["user"]}, "registration": "copy", "placement_directory": "shared-native"}}})
    assert shared_host == shared / "niri" and Path(report["etc"]) == shared_host
    override = {**env, "COMPFUZOR_NIRI_PROFILE": str(shared_host / "etc/keybinding-niri.json")}
    invoke(producer / "bin/install.mjs", override)
    received = Path(env["XDG_CONFIG_HOME"]) / "niri"
    assert (received / "shared-native/media-mute.binding.kdl").exists()
    assert not (received / f".keybindings/source/{MEDIA_NAME}/action/media-mute.yaml").is_symlink()
    assert not (shared_host / "bin/install-system.mjs").exists(), "shared material alone must not invent a system receiver"
    print("ok: both real receiver audiences from one home-local profile, explicit shared placement and consumer override")


def test_home_fallback(area: Path):
    env = environment(area)
    env.pop("XDG_DATA_HOME", None)
    directory, _ = render("niri.etc.pb", area / "fallback-render", env)
    assert directory == Path(env["HOME"]) / ".local/share/compfuzor/etc/niri"
    invoke(directory / "bin/install.mjs", env)
    invoke(directory / "bin/assemble.mjs", env, ["--check"])
    assert (Path(env["XDG_CONFIG_HOME"]) / "niri/config.kdl").exists()
    print("ok: target HOME fallback without XDG_DATA_HOME, not the controller account's home")


if __name__ == "__main__":
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text("# Action placement scratch\nActual playbook defaults in disposable HOME/XDG; isolated native receiver validation. Privileged/session commands are stubbed or never executed.\n")
    with tempfile.TemporaryDirectory(prefix="placement-", dir=SCRATCH) as tmp:
        env, deployed, umbrella_inputs = test_home_defaults(Path(tmp))
        test_system_fixture_and_shared(Path(tmp), env, deployed, umbrella_inputs)
        test_home_fallback(Path(tmp) / "fallback")
