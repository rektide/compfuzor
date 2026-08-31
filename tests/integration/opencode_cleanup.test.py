#!/usr/bin/env python3
"""Verify OpenCode's native-library cleanup age and apply behavior."""

from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CLEANUP = ROOT / "files/opencode/cleanup.sh"


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


def run_cleanup(directory: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(CLEANUP), "--tmp-dir", str(directory), *arguments],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def test_default_apply_removes_recent_inactive_library() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-cleanup-") as temporary:
        directory = Path(temporary)
        library = build_opentui_fixture(directory, ".abcdef-00000000.so")

        result = run_cleanup(directory, "--apply")

        if result.returncode != 0:
            raise AssertionError(f"cleanup failed:\n{result.stdout}{result.stderr}")
        if library.exists():
            raise AssertionError(f"recent inactive library was retained:\n{result.stdout}")
        if "eligible=1" not in result.stdout or "deleted=1" not in result.stdout:
            raise AssertionError(f"cleanup did not report deletion:\n{result.stdout}")


def test_explicit_minimum_age_retains_and_accounts_for_recent_library() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-cleanup-") as temporary:
        directory = Path(temporary)
        library = build_opentui_fixture(directory, ".abcdef-00000000.so")

        result = run_cleanup(directory, "--apply", "--min-age", "24h")

        if result.returncode != 0:
            raise AssertionError(f"cleanup failed:\n{result.stdout}{result.stderr}")
        if not library.exists():
            raise AssertionError(f"minimum age did not retain library:\n{result.stdout}")
        if "young=1" not in result.stdout or "young_bytes=" not in result.stdout:
            raise AssertionError(f"cleanup did not account for retained bytes:\n{result.stdout}")


if __name__ == "__main__":
    test_default_apply_removes_recent_inactive_library()
    test_explicit_minimum_age_retains_and_accounts_for_recent_library()
    print("ok: OpenCode native-library cleanup")
