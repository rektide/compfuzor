#!/usr/bin/env python3

"""Direct CLI tests for links.ts status: every row reports what actually sits at dest."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINKS_TS = ROOT / "files" / "links" / "links.ts"


def check(label: str, actual: object, expected: object) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"ok: {label}")


def check_contains(label: str, haystack: str, needle: str) -> None:
    if needle not in haystack:
        raise AssertionError(f"{label}: {needle!r} not found in {haystack!r}")
    print(f"ok: {label}")


def run(args: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["node", str(LINKS_TS), *args],
        capture_output=True,
        text=True,
        check=False,
        **kwargs,  # type: ignore[arg-type]
    )


def write_manifest(root: Path, records: list[dict]) -> Path:
    manifest = root / "links.json"
    manifest.write_text(
        json.dumps({"version": 1, "deployment": {"dir": str(root)}, "links": records}),
        encoding="utf-8",
    )
    return manifest


def record(dest: str, src: str, policy: str = "preserve") -> dict:
    return {
        "id": f"system:{dest}",
        "scope": "system",
        "src": src,
        "dest": dest,
        "policy": policy,
        "state": "present",
    }


def test_status_reports_actual() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-status-") as tmp:
        root = Path(tmp).resolve()
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        # foreign symlink pointing somewhere else entirely
        other = root / "other" / "app.conf"
        other.parent.mkdir()
        other.write_text("other\n", encoding="utf-8")
        foreign_dest = root / "foreign.conf"
        foreign_dest.symlink_to(other)

        # managed symlink -> plan src
        managed_dest = root / "managed.conf"
        managed_dest.symlink_to(src / "app.conf")

        # regular file squatting on dest with fail policy
        fail_dest = root / "fail.conf"
        fail_dest.write_text("squatter\n", encoding="utf-8")

        # no entry at all
        missing_dest = root / "missing.conf"

        manifest = write_manifest(
            root,
            [
                record("foreign.conf", plan_src),
                record("managed.conf", plan_src),
                record("fail.conf", plan_src, policy="fail"),
                record("missing.conf", plan_src),
            ],
        )

        result = run(["status", "--json", str(manifest)])
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        by_dest = {Path(row["dest"]).name: row for row in rows}

        check("manifest exit reflects drift (MISSING+CONFLICT present)", result.returncode, 1)
        check("foreign is OVERRIDE", by_dest["foreign.conf"]["status"], "OVERRIDE")
        check_contains(
            "foreign detail shows the actual target",
            by_dest["foreign.conf"]["detail"],
            f"symlink -> {other}",
        )
        check("managed is MANAGED", by_dest["managed.conf"]["status"], "MANAGED")
        check(
            "managed detail is the readlink truth",
            by_dest["managed.conf"]["detail"],
            f"symlink -> {plan_src}",
        )
        check("fail-policy squatter is CONFLICT", by_dest["fail.conf"]["status"], "CONFLICT")
        check_contains(
            "conflict detail says what actually sits there",
            by_dest["fail.conf"]["detail"],
            "regular file",
        )
        check("missing is MISSING", by_dest["missing.conf"]["status"], "MISSING")
        check("missing detail names the void", by_dest["missing.conf"]["detail"], "no entry")

        human = run(["status", str(manifest)])
        header = human.stdout.splitlines()[0]
        check_contains("human header has detail column", header, "detail")
        check_contains(
            "human line prints the actual foreign target",
            human.stdout,
            f"symlink -> {other}",
        )


def test_status_absent_and_directory() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-status-") as tmp:
        root = Path(tmp).resolve()
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        # state absent, but a managed link exists (ours, must go)
        should_be_absent = root / "stale.conf"
        should_be_absent.symlink_to(src / "app.conf")

        # directory occupying a present-record dest
        dir_dest = root / "dirdest"
        dir_dest.mkdir()

        manifest = write_manifest(
            root,
            [
                {**record("stale.conf", plan_src), "state": "absent"},
                record("dirdest", plan_src, policy="fail"),
            ],
        )
        result = run(["status", "--json", str(manifest)])
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        by_dest = {Path(row["dest"]).name: row for row in rows}

        check("absent-state violation is CONFLICT", by_dest["stale.conf"]["status"], "CONFLICT")
        check_contains(
            "absent conflict shows what it actually is",
            by_dest["stale.conf"]["detail"],
            f"symlink -> {plan_src}",
        )
        check("directory occupier is CONFLICT", by_dest["dirdest"]["status"], "CONFLICT")
        check_contains("directory conflict names the directory", by_dest["dirdest"]["detail"], "directory")


def main() -> None:
    test_status_reports_actual()
    test_status_absent_and_directory()
    print("all links status-actual checks passed")


if __name__ == "__main__":
    main()
