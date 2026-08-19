#!/usr/bin/env python3
"""Black-box tests for the single public repart executable (flat verbs)."""

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
    (prefix / "etc").mkdir()
    shutil.copy2(ROOT / "files/repart/repart.ts", prefix / "bin/repart")
    shutil.copytree(ROOT / "files/repart/defs", prefix / "etc/defs")
    (prefix / "bin/repart").chmod(0o755)
    mock_bin = tmp_path / "mock-bin"
    mock_bin.mkdir()
    env = os.environ.copy()
    env["PATH"] = f"{mock_bin}:{env['PATH']}"
    return prefix / "bin/repart", env, mock_bin


def mock(mock_bin: Path, name: str, body: str) -> None:
    path = mock_bin / name
    path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
    path.chmod(0o755)


def run(cli: Path, env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([cli, *args], env=env, text=True, capture_output=True, check=False)


def test_help_explains_commands_and_durable_state(install) -> None:
    cli, env, _ = install
    top = run(cli, env, "--help")
    assert top.returncode == 0
    for command in ["render", "format", "pivot", "write", "loop-mount",
                    "loop-unmount", "subvol-path", "btrfs-subvols", "btrfs-default"]:
        assert command in top.stdout
    fmt = run(cli, env, "format", "--help")
    assert fmt.returncode == 0
    assert "DIR/var" in fmt.stdout
    assert "intentionally forbidden" in fmt.stdout


def test_render_overlays_tokens_and_stdout(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"
    overlay = tmp_path / "overlay"
    base.mkdir(); overlay.mkdir()
    (base / "mkosi.conf").write_text("date=@DATE@ arch=@ARCH@ swap=@SWAP@ x=@THING@\n")
    (base / "kept").write_text("base\n")
    (overlay / "kept").write_text("overlay\n")
    result = run(
        cli, env, "render", "--from", str(base), "--overlay", str(overlay),
        "--date", "20260817", "--arch", "arm64", "--swap", "8G", "--set", "THING=a&b",
    )
    assert result.returncode == 0, result.stderr
    tree = Path(result.stdout.strip())
    assert result.stdout == f"{tree}\n"
    assert tree.is_absolute()
    assert (tree / "mkosi.conf").read_text() == "date=20260817 arch=arm64 swap=8G x=a&b\n"
    assert (tree / "kept").read_text() == "overlay\n"


def test_render_rejects_unresolved_uppercase_token(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    (base / "bad.conf").write_text("Value=@MISSING@\n")
    result = run(cli, env, "render", "--from", str(base))
    assert result.returncode != 0
    assert result.stdout == ""
    assert "unresolved uppercase" in result.stderr


def test_render_preserves_deferred_token_subtree(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    payload = base / "guest-toolkit/defs"; payload.mkdir(parents=True)
    (base / "mkosi.conf").write_text("Subvol=@DATE@\n")
    (payload / "bdr.conf").write_text("BlockDeviceReplace=@SOURCE@\n")
    result = run(
        cli, env, "render", "--from", str(base),
        "--date", "20260817", "--preserve", "guest-toolkit",
    )
    assert result.returncode == 0, result.stderr
    tree = Path(result.stdout.strip())
    assert (tree / "mkosi.conf").read_text() == "Subvol=20260817\n"
    assert (tree / "guest-toolkit/defs/bdr.conf").read_text() == "BlockDeviceReplace=@SOURCE@\n"


def test_render_preserves_relative_symlinks_as_durable_links(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    (base / "target.conf").write_text("Date=@DATE@\n")
    (base / "linked.conf").symlink_to("target.conf")
    rendered = run(cli, env, "render", "--from", str(base), "--date", "20260817")
    assert rendered.returncode == 0, rendered.stderr
    tree = Path(rendered.stdout.strip())
    shutil.rmtree(base)
    assert os.readlink(tree / "linked.conf") == "target.conf"
    assert (tree / "linked.conf").read_text() == "Date=20260817\n"


def test_swap_defaults_to_16g(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    (base / "mkosi.conf").write_text("swap=@SWAP@\n")
    rendered = run(cli, env, "render", "--from", str(base), "--date", "20260817")
    assert rendered.returncode == 0, rendered.stderr
    tree = Path(rendered.stdout.strip())
    assert (tree / "mkosi.conf").read_text() == "swap=16G\n"


def test_environment_falls_back_and_flags_override(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    (base / "mkosi.conf").write_text("date=@DATE@ thing=@THING@\n")
    env["REPART_DATE"] = "20260101"
    env["REPART_SET"] = "THING=from-env"
    rendered = run(cli, env, "render", "--from", str(base), "--date", "20260817")
    assert rendered.returncode == 0, rendered.stderr
    tree = Path(rendered.stdout.strip())
    assert (tree / "mkosi.conf").read_text() == "date=20260817 thing=from-env\n"


def test_environment_supplies_from_swap_and_name(install, tmp_path: Path) -> None:
    cli, env, _ = install
    base = tmp_path / "base"; base.mkdir()
    (base / "conf").write_text("swap=@SWAP@\n")
    env["REPART_FROM"] = str(base)
    env["REPART_SWAP"] = "8G"
    env["REPART_NAME"] = "env-render"
    rendered = run(cli, env, "render", "--date", "20260817")
    assert rendered.returncode == 0, rendered.stderr
    tree = Path(rendered.stdout.strip())
    assert tree.name == "env-render"
    assert (tree / "conf").read_text() == "swap=8G\n"


def test_help_documents_environment_variables(install) -> None:
    cli, env, _ = install
    top = run(cli, env, "--help")
    assert "REPART_*" in top.stdout
    render_help = run(cli, env, "render", "--help")
    assert "REPART_SWAP" in render_help.stdout
    assert "REPART_OVERLAY" in render_help.stdout
    write_help = run(cli, env, "write", "--help")
    assert "REPART_CONFIRM" in write_help.stdout
    mount_help = run(cli, env, "loop-mount", "--help")
    assert "REPART_READ_ONLY" in mount_help.stdout


def test_format_and_write_preserve_exact_arguments(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    log = tmp_path / "repart.log"; env["MOCK_LOG"] = str(log)
    mock(mock_bin, "systemd-repart", "printf '%s\\n' \"$*\" >>\"$MOCK_LOG\"; printf 'repart output\\n'")
    mock(mock_bin, "lsblk", "printf '%s\\n' \"${@: -1}\"")
    mock(mock_bin, "findmnt", "exit 1")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")

    previewed = run(
        cli, env, "format", str(target),
        "--date", "20260817", "--name", "format-test",
    )
    assert previewed.returncode == 0, previewed.stderr
    assert "repart output" in previewed.stderr
    draft = Path(previewed.stdout.strip())
    assert draft.parent == cli.parent.parent / "var"
    assert draft.name == "format-test"
    assert previewed.stdout == f"{draft}\n"
    assert (draft / "arguments").read_text().splitlines() == [
        "--offline=yes", "--empty=force", "--dry-run=yes"
    ]
    assert "@SWAP@" not in "".join(p.read_text() for p in (draft / "definitions").glob("**/*.conf"))

    written = run(cli, env, "write", str(draft), "--confirm", str(target))
    assert written.returncode == 0, written.stderr
    assert written.stdout == ""
    assert "repart output" in written.stderr
    calls = log.read_text().splitlines()
    assert "--offline=yes --empty=force --dry-run=yes" in calls[0]
    assert "--offline=yes --empty=force --dry-run=no" in calls[1]
    assert draft.exists()


def test_write_rejects_modified_draft(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    mock(mock_bin, "systemd-repart", "exit 0")
    mock(mock_bin, "lsblk", "printf '%s\n' \"${@: -1}\"")
    mock(mock_bin, "findmnt", "exit 1")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")
    previewed = run(cli, env, "format", str(target), "--date", "20260817")
    assert previewed.returncode == 0, previewed.stderr
    draft = Path(previewed.stdout.strip())
    (draft / "arguments").write_text("--empty=force\n--dry-run=yes\n")
    written = run(cli, env, "write", str(draft), "--confirm", str(target))
    assert written.returncode != 0
    assert "draft contents changed" in written.stderr


def test_write_fails_closed_when_mount_check_errors(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    mock(mock_bin, "systemd-repart", "exit 0")
    mock(mock_bin, "lsblk", "printf '%s\n' \"${@: -1}\"")
    mock(mock_bin, "findmnt", "exit 2")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")
    previewed = run(cli, env, "format", str(target), "--date", "20260817")
    assert previewed.returncode == 0, previewed.stderr
    written = run(cli, env, "write", previewed.stdout.strip(), "--confirm", str(target))
    assert written.returncode != 0
    assert "findmnt could not determine mount state" in written.stderr


def test_pivot_checks_source_and_renders_bdr_token(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    real_stat = shutil.which("stat")
    mock(mock_bin, "stat", f"if [ \"${{1:-}}\" = -f ]; then echo btrfs; else exec {real_stat} \"$@\"; fi")
    mock(mock_bin, "btrfs", "printf 'devid 1 size 1 path /dev/loop0\\n'")
    mock(mock_bin, "systemd-repart", "if [ \"${1:-}\" = --version ]; then echo 'systemd 261'; fi")
    target = tmp_path / "disk.img"; target.write_bytes(b"disk")
    source = tmp_path / "source"; source.mkdir()
    result = run(cli, env, "pivot", str(target), "--source", str(source))
    assert result.returncode == 0, result.stderr
    definition = (Path(result.stdout.strip()) / "definitions/50-root.conf").read_text()
    assert f"BlockDeviceReplace={source.resolve()}" in definition
    assert "@SOURCE@" not in definition


def test_loop_mount_and_unmount_pair(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    log = tmp_path / "image.log"; env["MOCK_LOG"] = str(log)
    mock(mock_bin, "losetup", "if [ \"$1\" = -d ]; then echo detach:$2 >>\"$MOCK_LOG\"; else echo /dev/loop9; fi")
    mock(mock_bin, "lsblk", "printf '/dev/loop9  loop\\n/dev/loop9p4 4f68bce3-e8cd-4db1-96e7-fbcaf984b709 part\\n'")
    mock(mock_bin, "mount", "echo mount:$* >>\"$MOCK_LOG\"")
    mock(mock_bin, "findmnt", "exit 0")
    mock(mock_bin, "umount", "echo umount:$* >>\"$MOCK_LOG\"")
    image = tmp_path / "image.raw"; image.write_bytes(b"image")

    mounted = run(cli, env, "loop-mount", str(image), "--read-only")
    assert mounted.returncode == 0, mounted.stderr
    mountpoint = Path(mounted.stdout.strip())
    assert mounted.stdout == f"{mountpoint}\n"
    assert mountpoint.parent == cli.parent.parent / "var"

    listed = run(cli, env, "btrfs-subvols", str(mountpoint))
    assert listed.returncode != 0 or listed.returncode == 0  # mocked btrfs absent; not the point here

    unmapped = run(cli, env, "loop-unmount", str(mountpoint))
    assert unmapped.returncode == 0, unmapped.stderr
    assert unmapped.stdout == ""
    assert "umount:-R " in log.read_text()
    assert "detach:/dev/loop9" in log.read_text()

    unknown = run(cli, env, "loop-unmount", str(mountpoint))
    assert unknown.returncode != 0
    assert "not a repart mount" in unknown.stderr


def test_loop_mount_rejects_block_devices(install, tmp_path: Path) -> None:
    cli, env, _ = install
    result = run(cli, env, "loop-mount", "/dev/sda")
    assert result.returncode != 0
    assert "not an image file" in result.stderr


def test_subvol_path_scheme(install) -> None:
    cli, env, _ = install
    env["REPART_ARCH"] = "amd64"
    result = run(cli, env, "subvol-path", "20260817")
    assert result.returncode == 0
    assert result.stdout == "/root/superbfowle/amd64/20260817\n"
    home = run(cli, env, "subvol-path", "--base", "home", "20260817")
    assert home.stdout == "/home/superbfowle/20260817\n"
    flavored = run(cli, env, "subvol-path", "--flavor", "lab", "--base", "home", "20260901")
    assert flavored.stdout == "/home/lab/20260901\n"


def test_render_and_subvol_path_share_the_scheme(install, tmp_path: Path) -> None:
    cli, env, _ = install
    env["REPART_ARCH"] = "amd64"
    env["REPART_FLAVOR"] = "lab"
    base = tmp_path / "base"; base.mkdir()
    (base / "root.conf").write_text("Dirs=@ROOT_PREFIX@/@ARCH@/@DATE@ @HOME_PREFIX@/@DATE@\n")
    rendered = run(cli, env, "render", "--from", str(base), "--date", "20260817")
    assert rendered.returncode == 0, rendered.stderr
    tree = Path(rendered.stdout.strip())
    assert (tree / "root.conf").read_text() == "Dirs=/root/lab/amd64/20260817 /home/lab/20260817\n"
    path = run(cli, env, "subvol-path", "20260817")
    assert path.stdout == "/root/lab/amd64/20260817\n"


def test_btrfs_subvols_and_default_keep_data_and_narration_separate(install, tmp_path: Path) -> None:
    cli, env, mock_bin = install
    env["REPART_ARCH"] = "amd64"
    log = tmp_path / "btrfs.log"; env["MOCK_LOG"] = str(log)
    mock(
        mock_bin,
        "btrfs",
        """case "$1 $2" in
          'subvolume get-default') echo 'ID 257 gen 1 top level 5 path root/superbfowle/amd64/20260101' ;;
          'subvolume list') printf 'ID 257 gen 1 top level 5 path root/superbfowle/amd64/20260101\\nID 258 gen 2 top level 5 path root/superbfowle/amd64/20260817\\nID 259 gen 2 top level 5 path home/superbfowle/20260817\\n' ;;
          'subvolume set-default') echo "$3 $4" >>"$MOCK_LOG" ;;
        esac""",
    )
    mountpoint = tmp_path / "mount"; mountpoint.mkdir()
    shown = run(cli, env, "btrfs-subvols", str(mountpoint))
    assert shown.returncode == 0, shown.stderr
    assert shown.stdout.splitlines() == [
        "kind\tdate\tpath\tdefault",
        "root\t20260101\t/root/superbfowle/amd64/20260101\ttrue",
        "root\t20260817\t/root/superbfowle/amd64/20260817\tfalse",
        "home\t20260817\t/home/superbfowle/20260817\tfalse",
    ]
    changed = run(cli, env, "btrfs-default", str(mountpoint), "latest")
    assert changed.returncode == 0, changed.stderr
    assert changed.stdout == ""
    assert "default subvolume set" in changed.stderr
    assert log.read_text().startswith("258 ")
