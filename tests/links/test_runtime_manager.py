#!/usr/bin/env python3
"""Black-box lifecycle tests for the deferred link runtime manager."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "files/links/links.ts"


def run(env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([CLI, *args], env=env, text=True, capture_output=True, check=False)


def write_manifest(path: Path, links: list[dict[str, str]]) -> None:
    path.write_text(json.dumps({"version": 1, "deployment": {"dir": str(path.parent)}, "links": links}))


def record(id: str, src: str, dest: str, policy: str = "preserve", state: str = "present") -> dict[str, str]:
    return {"id": id, "scope": "user", "src": src, "dest": dest, "policy": policy, "state": state}


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    value = os.environ.copy()
    value["HOME"] = str(tmp_path / "home")
    value["XDG_RUNTIME_DIR"] = str(tmp_path / "runtime")
    Path(value["HOME"]).mkdir()
    Path(value["XDG_RUNTIME_DIR"]).mkdir()
    return value


def test_apply_status_expansion_and_relative_target(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed")
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        record("home", str(source), "${HOME}/.config/example"),
        record("runtime", str(source), "${XDG_RUNTIME_DIR}/example"),
        record("tilde", str(source), "~/tilde-example"),
    ])
    applied = run(env, "apply", str(manifest), "--scope", "user", "--json-array")
    assert applied.returncode == 0, applied.stderr
    assert {row["action"] for row in json.loads(applied.stdout)} == {"created"}
    home_link = Path(env["HOME"]) / ".config/example"
    home_link.unlink(); home_link.symlink_to(os.path.relpath(source, home_link.parent))
    status = run(env, "status", str(manifest), "--json-array")
    assert status.returncode == 0, status.stderr
    assert {row["status"] for row in json.loads(status.stdout)} == {"MANAGED"}


def test_preserve_replace_overwrite_and_directory_safety(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed")
    preserved = tmp_path / "preserved"; preserved.write_text("foreign")
    replaced = tmp_path / "replaced"; replaced.write_text("foreign")
    failed = tmp_path / "failed"; failed.write_text("foreign")
    selected = tmp_path / "selected"; selected.write_text("foreign")
    directory = tmp_path / "directory"; directory.mkdir()
    fifo = tmp_path / "fifo"; os.mkfifo(fifo)
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        record("keep", str(source), str(preserved)),
        record("replace", str(source), str(replaced), "replace"),
        record("fail", str(source), str(failed), "fail"),
        record("select-this", str(source), str(selected)),
        record("directory", str(source), str(directory), "replace"),
        record("fifo", str(source), str(fifo), "replace"),
    ])
    selected_env = env | {"COMPFUZOR_LINK_OVERWRITE": "select-*"}
    applied = run(selected_env, "apply", str(manifest), "--json-array")
    assert applied.returncode == 1
    assert preserved.read_text() == "foreign"
    assert replaced.is_symlink() and replaced.resolve() == source
    assert failed.read_text() == "foreign"
    assert selected.is_symlink() and selected.resolve() == source
    assert directory.is_dir() and not directory.is_symlink()
    assert fifo.exists() and not fifo.is_symlink()


def test_remove_is_conservative_and_state_absent_applies(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed")
    managed = tmp_path / "managed"; managed.symlink_to(source)
    foreign_source = tmp_path / "foreign-source"; foreign_source.write_text("foreign")
    foreign = tmp_path / "foreign"; foreign.symlink_to(foreign_source)
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        record("managed", str(source), str(managed)),
        record("foreign", str(source), str(foreign)),
    ])
    source.unlink()  # A recorded target may be dangling by removal time.
    removed = run(env, "remove", str(manifest), "--json-array")
    assert removed.returncode == 0, removed.stderr
    assert not managed.exists() and not managed.is_symlink()
    assert foreign.is_symlink()

    source.write_text("managed")
    tombstone = tmp_path / "tombstone"; tombstone.symlink_to(source)
    write_manifest(manifest, [record("old", str(source), str(tombstone), state="absent")])
    applied = run(env, "apply", str(manifest))
    assert applied.returncode == 0, applied.stderr
    assert not tombstone.is_symlink()


def test_rejects_unsupported_runtime_expression_and_manifest_version(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed")
    untouched = tmp_path / "untouched"
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        record("valid", str(source), str(untouched)),
        record("bad", str(source), "${SHELL}/bad"),
    ])
    result = run(env, "apply", str(manifest), "--json-array")
    assert result.returncode == 2
    invalid = json.loads(result.stdout)
    assert invalid[0]["status"] == "INVALID"
    assert "unsupported runtime-root expression" in invalid[0]["detail"]
    assert not untouched.exists() and not untouched.is_symlink()
    manifest.write_text(json.dumps({"version": 2, "links": []}))
    result = run(env, "status", str(manifest))
    assert result.returncode == 2
    assert "unsupported version" in result.stderr


def test_audit_reports_cross_manifest_destination_conflicts(env: dict[str, str], tmp_path: Path) -> None:
    first_source = tmp_path / "first"; first_source.write_text("first")
    second_source = tmp_path / "second"; second_source.write_text("second")
    destination = tmp_path / "claimed"
    first = tmp_path / "one/links.json"; first.parent.mkdir()
    second = tmp_path / "two/links.json"; second.parent.mkdir()
    write_manifest(first, [record("one", str(first_source), str(destination))])
    write_manifest(second, [record("two", str(second_source), str(destination))])
    audited = run(env, "audit", str(first), str(second), "--json-array")
    assert audited.returncode == 1, audited.stderr
    assert {row["status"] for row in json.loads(audited.stdout)} == {"CONFLICT"}
