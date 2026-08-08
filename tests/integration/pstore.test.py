#!/usr/bin/env python3
"""Verify ramoops layout rejection and live/archive crash readout."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
STATUS = ROOT / "files/pstore/status-ramoops.sh"
DUMP = ROOT / "files/pstore/pstore-dump.sh"


def run_status(
    cmdline: str,
    klog: str = (
        "BIOS-e820: [mem 0x0000000100000000-0x000000103f37ffff] usable\n"
        "pstore: Registered ramoops as persistent store backend"
    ),
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["RAMOOPS_CMDLINE"] = cmdline
    env["RAMOOPS_KLOG"] = klog
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
        "ramoops.mem_address=0x100000000 ramoops.record_size=0x400000 "
        "ramoops.console_size=0x200000 "
        "ramoops.ftrace_size=0x100000 ramoops.pmsg_size=0x100000"
    )
    broken = run_status(f"ramoops.mem_size=0x400000 {common}")
    if broken.returncode != 1 or "DRIFT: no dmesg records" not in broken.stdout:
        raise AssertionError(
            f"zero-dmesg layout passed:\n{broken.stdout}{broken.stderr}"
        )

    balanced = run_status(f"ramoops.mem_size=0x1000000 {common}")
    if balanced.returncode != 0 or "3 record(s)" not in balanced.stdout:
        raise AssertionError(
            f"balanced layout failed:\n{balanced.stdout}{balanced.stderr}"
        )


def test_layout_requires_original_firmware_ram() -> None:
    cmdline = (
        "ramoops.mem_address=0x100000000 ramoops.mem_size=0x1000000 "
        "ramoops.record_size=0x400000 ramoops.console_size=0x200000 "
        "ramoops.ftrace_size=0x100000 ramoops.pmsg_size=0x100000"
    )
    registration = "pstore: Registered ramoops as persistent store backend"
    usable = run_status(
        cmdline,
        f"BIOS-e820: [mem 0x0000000100000000-0x000000103f37ffff] usable\n{registration}",
    )
    if usable.returncode != 0 or "inside original BIOS-e820" not in usable.stdout:
        raise AssertionError(f"usable firmware range failed:\n{usable.stdout}{usable.stderr}")

    mmio = run_status(
        cmdline,
        f"BIOS-e820: [mem 0x0000000200000000-0x000000103f37ffff] usable\n{registration}",
    )
    if mmio.returncode != 1 or "outside original BIOS-e820" not in mmio.stdout:
        raise AssertionError(f"unsafe firmware range passed:\n{mmio.stdout}{mmio.stderr}")

    unverifiable = run_status(cmdline, registration)
    if unverifiable.returncode != 1 or "BIOS-e820 usable ranges absent" not in unverifiable.stdout:
        raise AssertionError(
            f"unverifiable firmware range passed:\n{unverifiable.stdout}{unverifiable.stderr}"
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
    test_layout_requires_original_firmware_ram()
    test_dump_reads_live_and_archive()
    print("ok: pstore layout and record recovery")
