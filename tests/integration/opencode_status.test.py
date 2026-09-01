#!/usr/bin/env python3
"""Verify OpenCode status reporters: cleanup dry-run and shell ok-checker."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CLEANUP = ROOT / "files/opencode/cleanup.sh"
STATUS_CLEANUP = ROOT / "files/opencode/status-cleanup.sh"
STATUS_OK = ROOT / "files/opencode/status-opencode-ok.sh"


def build_opentui_fixture(directory: Path, name: str) -> Path:
    source = directory / "opentui.c"
    library = directory / name
    source.write_text("void opentui_fixture(void) {}\n", encoding="utf-8")
    subprocess.run(
        [
            "cc",
            "-shared",
            "-fPIC",
            "-Wl,-soname,libopentui.so",
            "-o",
            str(library),
            str(source),
        ],
        check=True,
    )
    return library


def stage_cleanup(dir_root: Path, script: str) -> Path:
    # status-cleanup.sh resolves the dry-run target as $DIR/bin/cleanup.sh.
    # files/ sources are 0644 (BINMODE applies at render), so stage an
    # executable copy the way bins.tasks would.
    bin_dir = dir_root / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    staged = bin_dir / "cleanup.sh"
    staged.write_text(script, encoding="utf-8")
    staged.chmod(0o755)
    return staged


def run_status_cleanup(dir_root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    environment = {**os.environ, "DIR": str(dir_root), "ENV_BYPASS": "1"}
    return subprocess.run(
        ["bash", str(STATUS_CLEANUP), "--no-timer", *arguments],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        env=environment,
        timeout=180,
    )


def fake_binary(path: Path, version_line: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!/bin/sh\necho '{version_line}'\n", encoding="utf-8")
    path.chmod(0o755)
    return path


def run_status_ok(environment: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(STATUS_OK), *arguments],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        env={**os.environ, **environment},
    )


def test_status_cleanup_reports_eligible_library_as_drift() -> None:
    # real cleanup.sh end-to-end (its /proc scan costs ~a minute on a loaded
    # host, so this is the suite's only real dry run)
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-status-") as temporary:
        root = Path(temporary)
        tmp = root / "tmp"
        tmp.mkdir()
        build_opentui_fixture(tmp, ".abcdef-00000000.so")
        stage_cleanup(root, CLEANUP.read_text(encoding="utf-8"))

        result = run_status_cleanup(root, "--tmp-dir", str(tmp))

        if result.returncode != 1:
            raise AssertionError(f"eligible library must drift:\n{result.stdout}{result.stderr}")
        if "eligible=1" not in result.stdout or "drift: 1 eligible leaked" not in result.stdout:
            raise AssertionError(f"eligibility not reported:\n{result.stdout}")


def test_status_cleanup_stub_clean_exits_zero() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-status-") as temporary:
        root = Path(temporary)
        stage_cleanup(
            root,
            "#!/bin/sh\necho 'dry-run summary: min_age=0s scanned=0 eligible=0 "
            "eligible_bytes=0B deleted=0 deleted_bytes=0B young=0 young_bytes=0B "
            "active=0 identity=0 content=0 changed=0'\n",
        )

        result = run_status_cleanup(root)

        if result.returncode != 0:
            raise AssertionError(f"clean summary must not drift:\n{result.stdout}{result.stderr}")
        if "ok: no eligible leaked native libraries" not in result.stdout:
            raise AssertionError(f"clean verdict missing:\n{result.stdout}")


def test_status_cleanup_stub_failure_exits_drift() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-status-") as temporary:
        root = Path(temporary)
        stage_cleanup(root, "#!/bin/sh\necho 'boom' >&2\nexit 3\n")

        result = run_status_cleanup(root)

        if result.returncode != 1:
            raise AssertionError(f"cleanup failure must drift:\n{result.stdout}{result.stderr}")
        if "drift: cleanup.sh failed" not in result.stdout:
            raise AssertionError(f"failure verdict missing:\n{result.stdout}")


def test_status_cleanup_without_cleanup_bin_is_not_applicable() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-status-") as temporary:
        root = Path(temporary)  # no bin/cleanup.sh staged

        result = run_status_cleanup(root)

        if result.returncode != 2:
            raise AssertionError(f"missing cleanup.sh must exit 2:\n{result.stdout}{result.stderr}")


def ok_environment(root: Path) -> tuple[Path, Path, dict[str, str]]:
    """A scratch managed deployment: working workspace + global link dir on PATH."""
    working = root / "working"
    global_bins = root / "gb"
    fake_binary(working / "dist/opencode2", "opencode2 v1.2.3-local-1")
    fake_binary(working / "dist/opencode2-node", "opencode2-node v1.2.3-local-1")
    global_bins.mkdir(parents=True, exist_ok=True)
    (global_bins / "opencode2").symlink_to(working / "dist/opencode2")
    (global_bins / "opencode2-node").symlink_to(working / "dist/opencode2-node")
    (global_bins / "opencode").symlink_to("opencode2")
    environment = {
        "OPENCODE_GLOBAL_BINS_DIR": str(global_bins),
        "OPENCODE_WORKING_DIR": str(working),
        "OPENCODE_PASSWORD": "test-only",
        "PATH": f"{global_bins}:{os.environ['PATH']}",
    }
    return working, global_bins, environment


def test_status_ok_passes_on_matching_deployment() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-statusok-") as temporary:
        _, _, environment = ok_environment(Path(temporary))

        result = run_status_ok(environment)

        if result.returncode != 0:
            raise AssertionError(f"matching deployment must pass:\n{result.stdout}{result.stderr}")
        if "ok: wrapper loaded" not in result.stdout:
            raise AssertionError(f"wrapper detection missing:\n{result.stdout}")


def test_status_ok_flags_wrapper_less_shell() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-statusok-") as temporary:
        _, _, environment = ok_environment(Path(temporary))
        del environment["OPENCODE_PASSWORD"]

        result = run_status_ok(environment)

        if result.returncode != 1:
            raise AssertionError(f"wrapper-less shell must drift:\n{result.stdout}{result.stderr}")
        if "wrapper not loaded" not in result.stdout:
            raise AssertionError(f"wrapper drift missing:\n{result.stdout}")


def test_status_ok_flags_version_mismatch_on_path() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-statusok-") as temporary:
        root = Path(temporary)
        _, _, environment = ok_environment(root)
        shadow = root / "shadow"
        fake_binary(shadow / "opencode2", "opencode2 v9.9.9-stale")
        environment["PATH"] = f"{shadow}:{environment['PATH']}"

        result = run_status_ok(environment)

        if result.returncode != 1:
            raise AssertionError(f"version mismatch must drift:\n{result.stdout}{result.stderr}")
        if "v9.9.9-stale" not in result.stdout or "does not match the managed binary" not in result.stdout:
            raise AssertionError(f"mismatch detail missing:\n{result.stdout}")


def test_status_ok_flags_broken_and_stale_links() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-statusok-") as temporary:
        root = Path(temporary)
        _, global_bins, environment = ok_environment(root)
        # broken: link to a never-built node target inside the workspace
        (global_bins / "opencode2-node").unlink()
        (global_bins / "opencode2-node").symlink_to(root / "working/dist/missing-opencode2-node")

        result = run_status_ok(environment)

        if result.returncode != 1:
            raise AssertionError(f"broken link must drift:\n{result.stdout}{result.stderr}")
        if "broken link" not in result.stdout:
            raise AssertionError(f"broken-link drift missing:\n{result.stdout}")

        # stale: node link resolves but points outside the working workspace
        outside = root / "outside"
        fake_binary(outside / "opencode2-node", "opencode2-node v1.2.3-local-1")
        (global_bins / "opencode2-node").unlink()
        (global_bins / "opencode2-node").symlink_to(outside / "opencode2-node")

        result = run_status_ok(environment)

        if result.returncode != 1:
            raise AssertionError(f"workspace escape must drift:\n{result.stdout}{result.stderr}")
        if "escapes the working workspace" not in result.stdout:
            raise AssertionError(f"escape drift missing:\n{result.stdout}")


if __name__ == "__main__":
    test_status_cleanup_reports_eligible_library_as_drift()
    test_status_cleanup_stub_clean_exits_zero()
    test_status_cleanup_stub_failure_exits_drift()
    test_status_cleanup_without_cleanup_bin_is_not_applicable()
    test_status_ok_passes_on_matching_deployment()
    test_status_ok_flags_wrapper_less_shell()
    test_status_ok_flags_version_mismatch_on_path()
    test_status_ok_flags_broken_and_stale_links()
    print("ok: OpenCode status reporters")
