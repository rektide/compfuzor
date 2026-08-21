#!/usr/bin/env python3

"""Direct CLI tests for links.ts status human output: verdict + both sides of each link."""

from __future__ import annotations

import json
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


def check_absent(label: str, haystack: str, needle: str) -> None:
    if needle in haystack:
        raise AssertionError(f"{label}: {needle!r} unexpectedly found in {haystack!r}")
    print(f"ok: {label}")


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["node", str(LINKS_TS), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def write_manifest(root: Path, records: list[dict]) -> Path:
    manifest = root / "links.json"
    manifest.write_text(
        json.dumps({"version": 1, "deployment": {"dir": str(root)}, "links": records}),
        encoding="utf-8",
    )
    return manifest


def record(dest: str, src: str, policy: str = "preserve", state: str = "present") -> dict:
    return {
        "id": f"system:{dest}",
        "scope": "system",
        "src": src,
        "dest": dest,
        "policy": policy,
        "state": state,
    }


def test_human_lines_show_both_sides() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-status-") as tmp:
        root = Path(tmp).resolve()
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        other = root / "other" / "app.conf"
        other.parent.mkdir()
        other.write_text("other\n", encoding="utf-8")
        foreign_dest = root / "foreign.conf"
        foreign_dest.symlink_to(other)

        managed_dest = root / "managed.conf"
        managed_dest.symlink_to(src / "app.conf")

        fail_dest = root / "fail.conf"
        fail_dest.write_text("squatter\n", encoding="utf-8")

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

        result = run(["status", str(manifest)])
        lines = result.stdout.splitlines()
        check("manifest exit reflects drift (MISSING+CONFLICT present)", result.returncode, 1)
        check("header is status/link", lines[0], "status\tlink")

        rows = {line.split("\t")[1].split(" ")[0]: line for line in lines[1:]}
        by_name = {Path(k).name: v for k, v in rows.items()}

        check_contains("managed shows both sides in one arrow", by_name["managed.conf"], f"ok\t{managed_dest} -> {plan_src}")
        check_absent("managed does not repeat wanted", by_name["managed.conf"], "wanted")
        check_contains(
            "override shows actual target and wanted src",
            by_name["foreign.conf"],
            f"override\t{foreign_dest} -> {other}\twanted {plan_src}",
        )
        check_contains("conflict names the squatter kind", by_name["fail.conf"], f"conflict\t{fail_dest} (file)")
        check_contains("conflict carries policy note", by_name["fail.conf"], "(fail policy)")
        check_contains("missing shows wanted side", by_name["missing.conf"], f"missing\t{missing_dest}\twanted {plan_src}")

        check_absent("no id column remains", result.stdout, "system:")
        check_absent("no scope column remains", result.stdout, "\tsystem\t")
        check_absent("no empty action columns", result.stdout, "\t\t")


def test_json_carries_structured_reality() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-status-") as tmp:
        root = Path(tmp).resolve()
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        other = root / "other" / "app.conf"
        other.parent.mkdir()
        other.write_text("other\n", encoding="utf-8")
        foreign_dest = root / "foreign.conf"
        foreign_dest.symlink_to(other)

        manifest = write_manifest(root, [record("foreign.conf", plan_src)])
        result = run(["status", "--json", str(manifest)])
        row = json.loads(result.stdout.splitlines()[0])
        check("json keeps machine status", row["status"], "OVERRIDE")
        check("json entry is symlink", row["entry"], "symlink")
        check("json target is the actual readlink", row["target"], str(other))
        check("json keeps id for glob/audit use", row["id"], "system:foreign.conf")


def test_apply_verbs_read_as_verbs() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-status-") as tmp:
        root = Path(tmp).resolve()
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        manifest = write_manifest(root, [record("new.conf", plan_src)])
        result = run(["apply", str(manifest)])
        check("apply exit ok", result.returncode, 0)
        check_contains("created verb leads the line", result.stdout, f"created\t{root / 'new.conf'} -> {plan_src}")

        again = run(["apply", str(manifest)])
        check_contains("second apply is unchanged", again.stdout, f"unchanged\t{root / 'new.conf'} -> {plan_src}")


def test_absent_and_directory() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-status-") as tmp:
        root = Path(tmp).resolve()
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        stale = root / "stale.conf"
        stale.symlink_to(src / "app.conf")
        dir_dest = root / "dirdest"
        dir_dest.mkdir()

        manifest = write_manifest(
            root,
            [
                record("stale.conf", plan_src, state="absent"),
                record("dirdest", plan_src, policy="fail"),
            ],
        )
        result = run(["status", str(manifest)])
        lines = {Path(line.split("\t")[1].split(" ")[0]).name: line for line in result.stdout.splitlines()[1:]}
        check_contains("absent violation names actual target", lines["stale.conf"], f"conflict\t{stale} -> {plan_src}")
        check_contains("absent note", lines["stale.conf"], "(should be absent)")
        check_contains("directory occupier named", lines["dirdest"], f"conflict\t{dir_dest} (directory)")
        check_contains("never-replaced note", lines["dirdest"], "(never replaced)")


def main() -> None:
    test_human_lines_show_both_sides()
    test_json_carries_structured_reality()
    test_apply_verbs_read_as_verbs()
    test_absent_and_directory()
    print("all links human-output checks passed")


if __name__ == "__main__":
    main()
