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


def write_manifest(path: Path, links: list[dict]) -> None:
    path.write_text(json.dumps({"version": 1, "deployment": {"dir": str(path.parent)}, "links": links}))


def record(id: str, src: str, dest: str, policy: str = "preserve", state: str = "present") -> dict:
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


def test_id_filter_selects_record_slice(env: dict[str, str], tmp_path: Path) -> None:
    # --id globs operate on record ids (scope:dest) alongside --scope, so a
    # caller can apply one slice of a plan (build-rust applies just the
    # version-manager links). No match is a clean no-op, not an error.
    source = tmp_path / "source"; source.write_text("managed")
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        record("user:/repo/a/.tool-versions", str(source), str(tmp_path / "a" / ".tool-versions")),
        record("user:/repo/a/mise.toml", str(source), str(tmp_path / "a" / "mise.toml")),
        record("user:/repo/a/bin/tool", str(source), str(tmp_path / "a" / "bin" / "tool")),
    ])
    applied = run(env, "apply", str(manifest), "--id", "*/.tool-versions,*/mise.toml", "--json-array")
    assert applied.returncode == 0, applied.stderr
    rows = json.loads(applied.stdout)
    assert {row["id"] for row in rows} == {"user:/repo/a/.tool-versions", "user:/repo/a/mise.toml"}
    assert not (tmp_path / "a" / "bin").exists()
    unmatched = run(env, "status", str(manifest), "--id", "nomatch-*")
    assert unmatched.returncode == 0, unmatched.stderr
    assert unmatched.stdout == ""  # A clean empty selection is silent.


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


def represented_record(id: str, src: Path, dest: Path, *, default: str = "link", policy: str = "replace", compose: bool = True) -> dict:
    return {
        **record(id, str(src), str(dest), policy),
        "strategies": {"available": ["link", "copy"], "default": default},
        "compose": compose,
    }


def test_declared_representations_are_both_healthy_and_nondefault_is_preserved(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_bytes(b"managed\x00bytes\n")
    linked = tmp_path / "linked"; linked.symlink_to(source)
    copied = tmp_path / "copied"; copied.write_bytes(source.read_bytes())
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        represented_record("linked", source, linked, default="copy"),
        represented_record("copied", source, copied, default="link"),
    ])

    status = run(env, "status", str(manifest), "--json-array")
    assert status.returncode == 0, status.stderr
    rows = {row["id"]: row for row in json.loads(status.stdout)}
    assert rows["linked"]["status"] == "MANAGED" and rows["linked"]["representation"] == "link"
    assert rows["copied"]["status"] == "MANAGED" and rows["copied"]["representation"] == "copy"

    applied = run(env, "apply", str(manifest), "--json-array")
    assert applied.returncode == 0, applied.stderr
    assert linked.is_symlink() and not copied.is_symlink()
    assert {row["action"] for row in json.loads(applied.stdout)} == {"unchanged"}


def test_default_creation_explicit_switch_and_unavailable_strategy(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed\n", encoding="utf-8")
    destination = tmp_path / "destination"
    untouched = tmp_path / "untouched"
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [represented_record("represented", source, destination, default="copy")])

    created = run(env, "apply", str(manifest), "--json-array")
    assert created.returncode == 0, created.stderr
    assert destination.is_file() and not destination.is_symlink()
    assert json.loads(created.stdout)[0]["representation"] == "copy"

    linked = run(env, "apply", str(manifest), "--strategy", "link", "--json-array")
    assert linked.returncode == 0, linked.stderr
    assert destination.is_symlink() and destination.resolve() == source
    assert json.loads(linked.stdout)[0]["action"] == "switched"

    copied = run(env, "apply", str(manifest), "--strategy", "copy", "--json-array")
    assert copied.returncode == 0, copied.stderr
    assert destination.is_file() and not destination.is_symlink() and destination.read_bytes() == source.read_bytes()

    write_manifest(manifest, [
        represented_record("represented", source, destination),
        record("link-only", str(source), str(untouched)),
    ])
    unavailable = run(env, "apply", str(manifest), "--strategy", "copy")
    assert unavailable.returncode == 2
    assert "strategy copy is unavailable for: link-only" in unavailable.stderr
    assert not untouched.exists() and not untouched.is_symlink()


def test_copy_drift_policy_directory_source_and_conservative_remove(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed\n", encoding="utf-8")
    preserved = tmp_path / "preserved"; preserved.write_text("modified\n", encoding="utf-8")
    replaced = tmp_path / "replaced"; replaced.write_text("modified\n", encoding="utf-8")
    failed = tmp_path / "failed"; failed.write_text("modified\n", encoding="utf-8")
    other = tmp_path / "other"; other.write_text("foreign\n", encoding="utf-8")
    foreign_link = tmp_path / "foreign-link"; foreign_link.symlink_to(other)
    dangling = tmp_path / "dangling"; dangling.symlink_to(tmp_path / "absent-target")
    directory = tmp_path / "directory"; directory.mkdir()
    missing_source = tmp_path / "missing-source"
    source_missing_dest = tmp_path / "source-missing"; source_missing_dest.write_text("old\n", encoding="utf-8")
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        represented_record("preserved", source, preserved, default="copy", policy="preserve"),
        represented_record("replaced", source, replaced, default="copy", policy="replace"),
        represented_record("failed", source, failed, default="copy", policy="fail"),
        represented_record("foreign-link", source, foreign_link, default="copy", policy="replace"),
        represented_record("dangling", source, dangling, default="copy", policy="fail"),
        represented_record("directory", source, directory, default="copy", policy="replace"),
        represented_record("missing-source", missing_source, source_missing_dest, default="copy", policy="replace"),
    ])
    result = run(env, "apply", str(manifest), "--json-array")
    assert result.returncode == 2
    rows = {row["id"]: row for row in json.loads(result.stdout)}
    assert rows["preserved"]["status"] == "OVERRIDE" and preserved.read_text() == "modified\n"
    assert rows["replaced"]["status"] == "MANAGED" and replaced.read_bytes() == source.read_bytes()
    assert rows["failed"]["status"] == "CONFLICT" and failed.read_text() == "modified\n"
    assert rows["foreign-link"]["status"] == "MANAGED" and not foreign_link.is_symlink() and foreign_link.read_bytes() == source.read_bytes()
    assert rows["dangling"]["status"] == "CONFLICT" and "dangling link" in rows["dangling"]["detail"]
    assert rows["directory"]["detail"] == "never replaced" and directory.is_dir()
    assert rows["missing-source"]["status"] == "SOURCE_MISSING" and source_missing_dest.read_text() == "old\n"

    matching = tmp_path / "matching"; matching.write_bytes(source.read_bytes())
    modified = tmp_path / "modified"; modified.write_text("changed\n", encoding="utf-8")
    unverifiable = tmp_path / "unverifiable"; unverifiable.write_text("managed\n", encoding="utf-8")
    write_manifest(manifest, [
        represented_record("matching", source, matching),
        represented_record("modified", source, modified),
        represented_record("unverifiable", missing_source, unverifiable),
    ])
    removed = run(env, "remove", str(manifest), "--json-array")
    assert removed.returncode == 0, removed.stderr
    assert not matching.exists()
    assert modified.read_text() == "changed\n" and unverifiable.read_text() == "managed\n"
    remove_rows = {row["id"]: row for row in json.loads(removed.stdout)}
    assert remove_rows["matching"]["action"] == "removed"
    assert remove_rows["modified"]["action"] == remove_rows["unverifiable"]["action"] == "preserved"


def test_composed_filter_keeps_direct_management_visible(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed\n", encoding="utf-8")
    composed = tmp_path / "composed"
    direct = tmp_path / "direct"
    manifest = tmp_path / "links.json"
    write_manifest(manifest, [
        represented_record("composed", source, composed),
        represented_record("direct", source, direct, compose=False),
    ])

    applied = run(env, "apply", str(manifest), "--composed", "--json-array")
    assert applied.returncode == 0, applied.stderr
    assert composed.is_symlink() and not direct.exists()
    assert [row["id"] for row in json.loads(applied.stdout)] == ["composed"]

    status = run(env, "status", str(manifest), "--json-array")
    assert status.returncode == 1
    assert {row["id"] for row in json.loads(status.stdout)} == {"composed", "direct"}

    direct_apply = run(env, "apply", str(manifest), "--id", "direct")
    assert direct_apply.returncode == 0, direct_apply.stderr
    assert direct.is_symlink()


def test_strategy_manifest_validation(env: dict[str, str], tmp_path: Path) -> None:
    source = tmp_path / "source"; source.write_text("managed")
    manifest = tmp_path / "links.json"
    bad_values = [
        ({"available": [], "default": "link"}, "non-empty array"),
        ({"available": ["magic"], "default": "magic"}, "unsupported strategy"),
        ({"available": ["link", "link"], "default": "link"}, "duplicates"),
        ({"available": ["link"], "default": "copy"}, "must be available"),
    ]
    for strategies, message in bad_values:
        item = record("bad", str(source), str(tmp_path / "dest"))
        item["strategies"] = strategies
        write_manifest(manifest, [item])
        result = run(env, "status", str(manifest))
        assert result.returncode == 2 and message in result.stderr
