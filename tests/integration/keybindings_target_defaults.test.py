#!/usr/bin/env python3
"""Advertised producer selection through stock tasks; consumer roles stay distinct."""
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
            if entry["name"].startswith("install-keybindings")}


def assert_common_targets(result: dict) -> None:
    manifest = files(result)["keybinding-producer.json"]["json"]
    assert manifest["targets"] == ["niri", "umbriel"]
    entries = installers(result)
    assert set(entries) == {"install-keybindings.sh"}
    entry = entries["install-keybindings.sh"]
    assert entry["scope"] == ["user"] and entry["run"] is False
    assert " install-offer " in entry["content"] and "--selection" in entry["content"]
    assert "--profile" not in entry["content"] and "COMPFUZOR_NIRI_PROFILE" not in entry["content"]
    assert files(result)["keybindings/selection.json"]["json"]["receivers"] is None
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
        assert files(subset)["keybinding-producer.json"]["json"]["targets"] == ["niri", "umbriel"]
        assert files(subset)["keybindings/selection.json"]["json"]["receivers"] == [{"id": "umbriel"}]
        assert set(installers(subset)) == {"install-keybindings.sh"}
        explicit = render(area, "explicit-host", {
            "KEYBINDING_ACTIONS": actions,
            "KEYBINDING_TARGETS": {"niri": {"consumer": "/selected/host", "context": "desktop", "scope": "user"}},
        }, env)
        assert set(installers(explicit)) == {"install-keybindings.sh"}
        assert files(explicit)["keybindings/selection.json"]["json"]["receivers"] == [{"id": "niri", "profile": {"path": "/selected/host/etc/keybinding-niri.json"}, "context": "desktop", "scope": "user"}]
        for name, targets in [("empty-map", {}), ("empty-list", [])]:
            empty = render(area, name, {"KEYBINDING_ACTIONS": actions, "KEYBINDING_TARGETS": targets}, env)
            assert files(empty)["keybinding-producer.json"]["json"]["targets"] == []
            assert files(empty)["keybindings/selection.json"]["json"]["receivers"] == []
            assert set(installers(empty)) == {"install-keybindings.sh"}  # still advertises owned offer

        custom = render(area, "custom-defaults", {
            "KEYBINDING_ACTIONS": actions,
            "selected_consumer": "/custom/host",
            "KEYBINDING_TARGET_DEFAULTS": {"umbriel": {"consumer": "{{ selected_consumer }}", "context": "user", "scope": "user"}},
        }, env)
        assert custom["explicit_targets"] is False
        assert_common_targets(custom)  # retired shared defaults must not revive hardcoded profiles

        combined = render(area, "combined", {
            "KEYBINDING_ACTIONS": actions,
            "KEYBINDING_CONSUMERS": {"umbriel": {}}, "KEYBINDING_TARGETS": ["umbriel"],
        }, env)
        assert files(combined)["keybinding-umbriel.json"]["json"]["userSources"] == []
        assert files(combined)["keybinding-producer.json"]["json"]["targets"] == ["niri", "umbriel"]
        assert " host " in installers(combined)["install-keybindings-umbriel.sh"]["content"]
        selection = files(combined)["keybindings/selection.json"]["json"]
        assert selection["receivers"] == [{"id": "umbriel"}]
        assert selection["prospectiveConsumers"]["user"] == [{"path": str(area / "combined/payload/etc/keybindings/consumers/user/umbriel.json")}]
        assert list(installers(combined)) == ["install-keybindings-umbriel.sh", "install-keybindings.sh"]
        print("ok: advertised default-all/subset/empty producer selection, passive generation, host layers and prospective owned receivers")


if __name__ == "__main__":
    test_target_defaults()
