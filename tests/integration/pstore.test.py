#!/usr/bin/env python3
"""Verify ramoops layout rejection and live/archive crash readout."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
STATUS = ROOT / "files/kernel/status-ramoops.sh"
DUMP = ROOT / "files/kernel/pstore-dump.sh"


def run_status(cmdline: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["RAMOOPS_CMDLINE"] = cmdline
    env["RAMOOPS_KLOG"] = "pstore: Registered ramoops as persistent store backend"
    return subprocess.run(
        ["bash", str(STATUS)],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def test_layout_requires_dmesg_record() -> None:
    common = (
        "ramoops.record_size=0x4000 ramoops.console_size=0x20000 "
        "ramoops.ftrace_size=0x10000 ramoops.pmsg_size=0x10000"
    )
    broken = run_status(f"ramoops.mem_size=0x40000 {common}")
    if broken.returncode != 1 or "DRIFT: no dmesg records" not in broken.stdout:
        raise AssertionError(
            f"zero-dmesg layout passed:\n{broken.stdout}{broken.stderr}"
        )

    balanced = run_status(f"ramoops.mem_size=0x80000 {common}")
    if balanced.returncode != 0 or "16 record(s)" not in balanced.stdout:
        raise AssertionError(
            f"balanced layout failed:\n{balanced.stdout}{balanced.stderr}"
        )


def test_dump_reads_live_and_archive() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-pstore-") as temporary:
        root = Path(temporary)
        live = root / "live"
        archive = root / "archive/123/001"
        live.mkdir()
        archive.mkdir(parents=True)
        (live / "dmesg-ramoops-0").write_text("live panic\n", encoding="utf-8")
        (archive / "dmesg-ramoops-1").write_text("archived panic\n", encoding="utf-8")

        env = os.environ.copy()
        env["PSTORE_DIR"] = str(live)
        env["PSTORE_ARCHIVE_DIR"] = str(root / "archive")
        result = subprocess.run(
            ["bash", str(DUMP)],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 1:
            raise AssertionError(
                f"record readout returned {result.returncode}: {result.stderr}"
            )
        for expected in ("live panic", "archived panic"):
            if expected not in result.stdout:
                raise AssertionError(f"missing {expected!r}:\n{result.stdout}")


if __name__ == "__main__":
    test_layout_requires_dmesg_record()
    test_dump_reads_live_and_archive()
    print("ok: pstore layout and record recovery")
