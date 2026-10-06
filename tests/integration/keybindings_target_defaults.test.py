#!/usr/bin/env python3
"""Common producer wiring through stock tasks; consumer roles and overrides stay distinct."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/keybindings-target-defaults"


def render(area: Path, name: str, declarations: dict, env: dict) -> dict:
    directory = area / name
    directory.mkdir()
    payload = directory / "payload"
    variables = {
        "TYPE": name, "NAME": name, "DIR": str(payload),
        "ETC": str(payload / "etc"), "BINS_DIR": str(payload / "bin"),
        "ETC_FILES": [], "BINS": [], "DIRS": [], "PKGS": [],
        "ACTION_AUDIENCES": {"default": "user"}, **declarations,
    }
    # Use the real entry condition: common targets alone must not activate generation.
    entry = next(task for task in yaml.safe_load((ROOT / "tasks/compfuzor.includes").read_text())
                 if task.get("import_tasks") == "compfuzor/gen_keybindings.tasks")
    playbook = directory / "render.pb"
    result_path = directory / "result.json"
    playbook.write_text(yaml.safe_dump([{
        "hosts": "all", "gather_facts": False, "vars": variables,
        "tasks": [
            {"include_defaults": {"file": str(ROOT / "vars/common.yaml")}},
            {**entry, "import_tasks": str(ROOT / "tasks/compfuzor/gen_keybindings.tasks")},
            {"copy": {"dest": str(result_path), "content": "{{ {'compiled': _keybindings_compiled | default({}), 'pkgs': PKGS, 'explicit_targets': KEYBINDING_TARGETS is defined} | to_nice_json }}"}},
        ],
    }], sort_keys=False))
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        cwd=ROOT, env=env, text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    # These tasks package data only: no receiver or deployment outputs were installed.
    assert not payload.exists()
    assert not (Path(env["HOME"]) / ".config").exists()
    return json.loads(result_path.read_text())


def files(result: dict) -> dict:
    return {entry["name"]: entry for entry in result["compiled"]["files"]}


def installers(result: dict) -> dict:
    return {entry["name"]: entry for entry in result["compiled"]["bins"]
            if entry["name"].startswith("install-keybindings-")}


def assert_common_targets(result: dict) -> None:
    manifest = files(result)["keybinding-producer.json"]["json"]
    assert manifest["targets"] == ["niri", "umbriel"]
    entries = installers(result)
    assert set(entries) == {f"install-keybindings-{target}.sh" for target in manifest["targets"]}
    for target in manifest["targets"]:
        entry = entries[f"install-keybindings-{target}.sh"]
        assert entry["scope"] == ["user"] and entry["run"] is False
        assert " install " in entry["content"] and "--profile-selector" in entry["content"]
        assert f"COMPFUZOR_{target.upper()}_PROFILE" in entry["content"]
        assert f"${{XDG_DATA_HOME}}/compfuzor/etc/{target}/etc/keybinding-{target}.json" in entry["content"]
    assert result["pkgs"] == ["jq"]
    assert result["explicit_targets"] is False


def test_target_defaults() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    if not (SCRATCH / "README.md").exists():
        (SCRATCH / "README.md").write_text(
            "# Common keybinding targets scratch\nStock include_defaults and generator fixtures; no live installs.\n"
        )
    with tempfile.TemporaryDirectory(prefix="defaults-", dir=SCRATCH) as tmp:
        area = Path(tmp)
        home = area / "home"
        home.mkdir()
        env = {**os.environ, "HOME": str(home), "TMPDIR": str(SCRATCH),
               "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        for name, declarations in [
            ("passive", {}),
            ("targets-only", {"KEYBINDING_TARGETS": ["niri"]}),
        ]:
            assert render(area, name, declarations, env)["compiled"] == {}

        actions = {"open": {"exec": ["foot"]}}
        producer = render(area, "actions-only", {"KEYBINDING_ACTIONS": actions}, env)
        assert_common_targets(producer)
        assert files(producer)["action/open.yaml"]["yaml"]["exec"] == ["foot"]
        for name, declarations in [
            ("bindings-only", {"KEYBINDINGS": {}}),
            ("empty-producer", {"KEYBINDING_ACTIONS": {}, "KEYBINDINGS": {}}),
            ("empty-consumers", {"KEYBINDING_ACTIONS": {}, "KEYBINDING_CONSUMERS": {}}),
            ("null-consumers", {"KEYBINDING_ACTIONS": {}, "KEYBINDING_CONSUMERS": None}),
        ]:
            empty = render(area, name, declarations, env)
            assert_common_targets(empty)
            assert files(empty)["keybinding-producer.json"]["json"]["resources"] == []

        host = render(area, "host", {"KEYBINDING_CONSUMERS": {"niri": {}, "umbriel": {}}}, env)
        assert "keybinding-producer.json" not in files(host)
        assert all(" host " in entry["content"] for entry in installers(host).values())
        patched = render(area, "patched-host", {
            "KEYBINDING_CONSUMERS": {"umbriel": {}},
            "KEYBINDINGS": {"open": {"patch": True, "umbriel": {"keys": ["Mod+Grave"]}}},
        }, env)
        assert "keybinding-producer.json" not in files(patched)
        profile = files(patched)["keybinding-umbriel.json"]["json"]
        assert profile["userSources"] == [{
            "path": {"path": str(area / "patched-host/payload/etc/keybinding/open.yaml")},
            "whenPresent": True,
        }]
        assert set(installers(patched)) == {"install-keybindings-umbriel.sh"}
        assert " host " in installers(patched)["install-keybindings-umbriel.sh"]["content"]

        subset = render(area, "subset", {"KEYBINDING_ACTIONS": actions, "KEYBINDING_TARGETS": ["umbriel"]}, env)
        assert files(subset)["keybinding-producer.json"]["json"]["targets"] == ["umbriel"]
        assert set(installers(subset)) == {"install-keybindings-umbriel.sh"}
        assert "--profile" not in installers(subset)["install-keybindings-umbriel.sh"]["content"]
        explicit = render(area, "explicit-host", {
            "KEYBINDING_ACTIONS": actions,
            "KEYBINDING_TARGETS": {"niri": {"consumer": "/selected/host", "context": "desktop", "scope": "user"}},
        }, env)
        assert set(installers(explicit)) == {"install-keybindings-niri.sh"}
        command = installers(explicit)["install-keybindings-niri.sh"]["content"]
        assert "--profile /selected/host/etc/keybinding-niri.json" in command
        assert "--context desktop --scope user" in command
        for name, targets in [("empty-map", {}), ("empty-list", [])]:
            empty = render(area, name, {"KEYBINDING_ACTIONS": actions, "KEYBINDING_TARGETS": targets}, env)
            assert files(empty)["keybinding-producer.json"]["json"]["targets"] == []
            assert installers(empty) == {}

        custom = render(area, "custom-defaults", {
            "KEYBINDING_ACTIONS": actions,
            "selected_consumer": "/custom/host",
            "KEYBINDING_TARGET_DEFAULTS": {"umbriel": {"consumer": "{{ selected_consumer }}", "context": "user", "scope": "user"}},
        }, env)
        assert custom["explicit_targets"] is False
        assert files(custom)["keybinding-producer.json"]["json"]["targets"] == ["umbriel"]
        assert "--profile /custom/host/etc/keybinding-umbriel.json" in installers(custom)["install-keybindings-umbriel.sh"]["content"]

        combined = render(area, "combined", {
            "KEYBINDING_ACTIONS": actions,
            "KEYBINDING_CONSUMERS": {"umbriel": {}}, "KEYBINDING_TARGETS": ["umbriel"],
        }, env)
        assert files(combined)["keybinding-umbriel.json"]["json"]["userSources"] == []
        assert files(combined)["keybinding-producer.json"]["json"]["targets"] == ["umbriel"]
        assert " install " in installers(combined)["install-keybindings-umbriel.sh"]["content"]
        print("ok: shared producer targets, passive defaults, empty reinstalls, consumer layers and explicit overrides")


if __name__ == "__main__":
    test_target_defaults()
