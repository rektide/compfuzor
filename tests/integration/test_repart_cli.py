#!/usr/bin/env python3
"""Black-box tests for the single public repart executable."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def install(tmp_path: Path) -> tuple[Path, dict[str, str], Path]:
    prefix = tmp_path / "repart-main"
    (prefix / "bin").mkdir(parents=True)
    (prefix / "libexec/repart").mkdir(parents=True)
    (prefix / "etc").mkdir()
    shutil.copy2(ROOT / "files/repart/repart", prefix / "bin/repart")
    shutil.copytree(ROOT / "files/repart/libexec", prefix / "libexec/repart", dirs_exist_ok=True)
    shutil.copytree(ROOT / "files/repart/defs", prefix / "etc/defs")
    for script in [prefix / "bin/repart", *(prefix / "libexec/repart").glob("*.sh")]:
        script.chmod(0o755)
    mock_bin = tmp_path / "mock-bin"
    mock_bin.mkdir()
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env['PATH']}"
    env["REPART_SCRATCH"] = str(tmp_path / "scratch")
    return prefix / "bin/repart", env, mock_bin


def mock(mock_bin: Path, name: str, body: str) -> None:
    path = mock_bin / name
    path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
    path.chmod(0o755)


def run(cli: Path, env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([cli, *args], env=env, text=True, capture_output=True, check=False)


def test_profile_render_overlays_tokens_and_stdout(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"
    overlay = tmp_path / "overlay"
    base.mkdir(); overlay.mkdir()
    (base / "mkosi.conf").write_text("date=@DATE@ arch=@ARCH@ swap=@SWAP@ x=@THING@\n")
    (base / "kept").write_text("base\n")
    (overlay / "kept").write_text("overlay\n")
    result = run(
        cli, env, "profile", "render", "--base", str(base), "--overlay", str(overlay),
        "--date", "20260817", "--arch", "arm64", "--swap", "8G", "--set", "THING=a&b",
    )
    assert result.returncode == 0, result.stderr
    tree = Path(result.stdout.strip())
    assert result.stdout == f"{tree}\n"
    assert tree.is_absolute()
    assert (tree / "mkosi.conf").read_text() == "date=20260817 arch=arm64 swap=8G x=a&b\n"
    assert (tree / "kept").read_text() == "overlay\n"


def test_profile_rejects_unresolved_uppercase_token(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    (base / "bad.conf").write_text("Value=@MISSING@\n")
    result = run(cli, env, "profile", "render", "--base", str(base))
    assert result.returncode != 0
    assert result.stdout == ""
    assert "unresolved uppercase" in result.stderr


def test_profile_preserves_deferred_token_subtree(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    payload = base / "guest-toolkit/defs"; payload.mkdir(parents=True)
    (base / "mkosi.conf").write_text("Slot=@DATE@\n")
    (payload / "bdr.conf").write_text("BlockDeviceReplace=@SOURCE@\n")
    result = run(
        cli, env, "profile", "render", "--base", str(base),
        "--date", "20260817", "--preserve", "guest-toolkit",
    )
    assert result.returncode == 0, result.stderr
    tree = Path(result.stdout.strip())
    assert (tree / "mkosi.conf").read_text() == "Slot=20260817\n"
    assert (tree / "guest-toolkit/defs/bdr.conf").read_text() == "BlockDeviceReplace=@SOURCE@\n"


def test_format_plan_and_apply_preserve_exact_arguments(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    log = tmp_path / "repart.log"; env["MOCK_LOG"] = str(log)
    mock(mock_bin, "systemd-repart", "printf '%s\\n' \"$*\" >>\"$MOCK_LOG\"")
    mock(mock_bin, "lsblk", "printf '%s\\n' \"${@: -1}\"")
    mock(mock_bin, "findmnt", "exit 1")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")

    planned = run(cli, env, "disk", "plan", "format", str(target), "--date", "20260817")
    assert planned.returncode == 0, planned.stderr
    plan = Path(planned.stdout.strip())
    assert planned.stdout == f"{plan}\n"
    assert (plan / "arguments").read_text().splitlines() == [
        "--offline=yes", "--empty=force", "--dry-run=yes"
    ]
    assert "@SWAP@" not in "".join(p.read_text() for p in (plan / "definitions").glob("*.conf"))

    applied = run(cli, env, "disk", "apply", str(plan), "--confirm", str(target))
    assert applied.returncode == 0, applied.stderr
    assert applied.stdout == ""
    calls = log.read_text().splitlines()
    assert "--offline=yes --empty=force --dry-run=yes" in calls[0]
    assert "--offline=yes --empty=force --dry-run=no" in calls[1]
    assert plan.exists()


def test_disk_apply_rejects_modified_plan(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    mock(mock_bin, "systemd-repart", "exit 0")
    mock(mock_bin, "lsblk", "printf '%s\n' \"${@: -1}\"")
    mock(mock_bin, "findmnt", "exit 1")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")
    planned = run(cli, env, "disk", "plan", "format", str(target), "--date", "20260817")
    assert planned.returncode == 0, planned.stderr
    plan = Path(planned.stdout.strip())
    (plan / "arguments").write_text("--empty=force\n--dry-run=yes\n")
    applied = run(cli, env, "disk", "apply", str(plan), "--confirm", str(target))
    assert applied.returncode != 0
    assert "plan contents changed" in applied.stderr


def test_migrate_checks_source_and_renders_bdr_token(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    real_stat = shutil.which("stat")
    mock(mock_bin, "stat", f"if [ \"${{1:-}}\" = -f ]; then echo btrfs; else exec {real_stat} \"$@\"; fi")
    mock(mock_bin, "btrfs", "printf 'devid 1 size 1 path /dev/loop0\\n'")
    mock(mock_bin, "systemd-repart", "if [ \"${1:-}\" = --version ]; then echo 'systemd 261'; fi")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")
    source = tmp_path / "source"; source.mkdir()
    result = run(cli, env, "disk", "plan", "migrate", str(target), "--source", str(source))
    assert result.returncode == 0, result.stderr
    definition = (Path(result.stdout.strip()) / "definitions/50-root.conf").read_text()
    assert f"BlockDeviceReplace={source.resolve()}" in definition
    assert "@SOURCE@" not in definition


def test_image_with_exports_context_and_cleans_owned_resources(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    log = tmp_path / "image.log"; env["MOCK_LOG"] = str(log)
    mock(mock_bin, "losetup", "if [ \"$1\" = -d ]; then echo detach:$2 >>\"$MOCK_LOG\"; else echo /dev/loop9; fi")
    mock(mock_bin, "lsblk", "printf '/dev/loop9  loop\\n/dev/loop9p4 4f68bce3-e8cd-4db1-96e7-fbcaf984b709 part\\n'")
    mock(mock_bin, "mount", "echo mount:$* >>\"$MOCK_LOG\"")
    mock(mock_bin, "findmnt", "exit 0")
    mock(mock_bin, "umount", "echo umount:$* >>\"$MOCK_LOG\"")
    image = tmp_path / "image.raw"; image.write_bytes(b"image")
    result = run(
        cli, env, "image", "with", str(image), "--read-only", "--", "sh", "-c",
        "printf '%s|%s|%s|%s\\n' \"$REPART_IMAGE\" \"$REPART_LOOP\" \"$REPART_DEVICE\" \"$REPART_MOUNT\"",
    )
    assert result.returncode == 0, result.stderr
    fields = result.stdout.strip().split("|")
    assert fields[:3] == [str(image.resolve()), "/dev/loop9", "/dev/loop9p4"]
    assert not Path(fields[3]).exists()
    assert "umount:-R " in log.read_text()
    assert "detach:/dev/loop9" in log.read_text()


def test_slot_public_path(install) -> None:
    cli, env, _ = install
    env["REPART_ARCH"] = "amd64"
    result = run(cli, env, "slot", "path", "20260817")
    assert result.returncode == 0
    assert result.stdout == "/os/superbfowle/amd64/20260817\n"
    home = run(cli, env, "slot", "path", "--home", "20260817")
    assert home.stdout == "/home/superbfowle/20260817\n"


def test_profile_and_slot_share_scheme_prefixes(install, tmp_path: Path) -> None:
    cli, env, _ = install
    env["REPART_ARCH"] = "amd64"
    env["REPART_OS_PREFIX"] = "/systems/os"
    env["REPART_HOME_PREFIX"] = "/systems/home"
    base = tmp_path / "base"; base.mkdir()
    (base / "root.conf").write_text("Dirs=@OS_PREFIX@/@ARCH@/@DATE@ @HOME_PREFIX@/@DATE@\n")
    rendered = run(cli, env, "profile", "render", "--base", str(base), "--date", "20260817")
    assert rendered.returncode == 0, rendered.stderr
    tree = Path(rendered.stdout.strip())
    assert (tree / "root.conf").read_text() == "Dirs=/systems/os/amd64/20260817 /systems/home/20260817\n"
    path = run(cli, env, "slot", "path", "20260817")
    assert path.stdout == "/systems/os/amd64/20260817\n"


def test_slot_show_and_set_keep_data_and_narration_separate(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    env["REPART_ARCH"] = "amd64"
    log = tmp_path / "btrfs.log"; env["MOCK_LOG"] = str(log)
    mock(
        mock_bin,
        "btrfs",
        """case "$1 $2" in
          'subvolume get-default') echo 'ID 257 gen 1 top level 5 path os/superbfowle/amd64/20260101' ;;
          'subvolume list') printf 'ID 257 gen 1 top level 5 path os/superbfowle/amd64/20260101\\nID 258 gen 2 top level 5 path os/superbfowle/amd64/20260817\\nID 259 gen 2 top level 5 path home/superbfowle/20260817\\n' ;;
          'subvolume set-default') echo "$3 $4" >>"$MOCK_LOG" ;;
        esac""",
    )
    mountpoint = tmp_path / "mount"; mountpoint.mkdir()
    shown = run(cli, env, "slot", "show", str(mountpoint))
    assert shown.returncode == 0, shown.stderr
    assert shown.stdout.splitlines() == [
        "kind\tdate\tpath\tdefault",
        "os\t20260101\t/os/superbfowle/amd64/20260101\ttrue",
        "os\t20260817\t/os/superbfowle/amd64/20260817\tfalse",
        "home\t20260817\t/home/superbfowle/20260817\tfalse",
    ]
    changed = run(cli, env, "slot", "set", str(mountpoint), "latest")
    assert changed.returncode == 0, changed.stderr
    assert changed.stdout == ""
    assert "default slot set" in changed.stderr
    assert log.read_text().startswith("258 ")
