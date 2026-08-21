#!/usr/bin/env python3

"""Direct CLI tests for links.ts status human output: verdict + both sides of each link."""

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


def check_absent(label: str, haystack: str, needle: str) -> None:
    if needle in haystack:
        raise AssertionError(f"{label}: {needle!r} unexpectedly found in {haystack!r}")
    print(f"ok: {label}")


def run(args: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["node", str(LINKS_TS), *args],
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, **(env or {})},
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
        check("header names all five columns", lines[0], "status\tdest\tsrc\tactual\tnote")

        rows = {line.split("\t")[1]: line for line in lines[1:]}
        by_name = {Path(k).name: v for k, v in rows.items()}

        check("managed line fills all five columns", by_name["managed.conf"], f'ok\t{managed_dest}\t{plan_src}\t{plan_src}\t""')
        check_absent("managed does not repeat wanted", by_name["managed.conf"], "wanted")
        check(
            "override line: actual target and wanted in their columns",
            by_name["foreign.conf"],
            f'override\t{foreign_dest}\t{plan_src}\t{other}\t""',
        )
        check("conflict row columns", by_name["fail.conf"].split("\t"), ["conflict", str(fail_dest), plan_src, "(file)", "(fail policy)"])
        check_contains("conflict carries policy note", by_name["fail.conf"], "(fail policy)")
        check("missing row: empty actual, wanted in its column", by_name["missing.conf"].split("\t"), ["missing", str(missing_dest), plan_src, "\"\"", "\"\""])

        check_absent("no id column remains", result.stdout, "system:")
        check_absent("no scope column remains", result.stdout, "\tsystem\t")
        check("every row has all five columns", {len(line.split("\t")) for line in result.stdout.splitlines()}, {5})


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
        check_contains("created verb leads the line", result.stdout, f"created\t{root / 'new.conf'}\t{plan_src}")

        again = run(["apply", str(manifest)])
        check("satisfied apply is silent", again.stdout, "")
        check("satisfied apply still exits 0", again.returncode, 0)


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
        lines = {Path(line.split("\t")[1]).name: line for line in result.stdout.splitlines()[1:]}
        check("absent violation row columns", lines["stale.conf"].split("\t"), ["conflict", str(stale), "\"\"", plan_src, "(should be absent)"])
        check_contains("absent note", lines["stale.conf"], "(should be absent)")
        check("directory occupier columns", lines["dirdest"].split("\t"), ["conflict", str(dir_dest), plan_src, "(directory)", "(never replaced)"])
        check_contains("never-replaced note", lines["dirdest"], "(never replaced)")


def test_apply_routes_mutations_through_sudo() -> None:
    """COMPFUZOR_LINKS_SUDO=1 must create links via the sudo shell-out path.

    A PATH-shim `sudo` that just execs its arguments exercises the execFile
    branch without needing root.
    """
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-sudo-") as tmp:
        root = Path(tmp).resolve()
        shim_dir = root / "shim"
        shim_dir.mkdir()
        (shim_dir / "sudo").write_text('#!/bin/sh\nexec "$@"\n', encoding="utf-8")
        (shim_dir / "sudo").chmod(0o755)

        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")

        # pre-existing foreign squatter, policy replace: the sudo path must
        # rm it and link over it
        dest = root / "dest.conf"
        dest.write_text("squatter\n", encoding="utf-8")

        manifest = write_manifest(root, [record("dest.conf", plan_src, policy="replace")])
        result = run(
            ["apply", str(manifest)],
            env={
                "COMPFUZOR_LINKS_SUDO": "1",
                "PATH": f"{shim_dir}:{os.environ['PATH']}",
            },
        )
        check("sudo-path apply exits ok", result.returncode, 0)
        check_contains("sudo-path reports replaced", result.stdout, "replaced")
        check("dest is now a symlink to src", str(os.readlink(dest)), plan_src)


def make_sudo_shim(root: Path) -> Path:
    """PATH shim that logs each sudo invocation and execs its arguments."""
    shim_dir = root / "shim"
    shim_dir.mkdir(exist_ok=True)
    log = root / "sudo.log"
    (shim_dir / "sudo").write_text(
        "#!/bin/sh\n"
        f'printf \'"%s"\\n\' "$@" >> {log}\n'
        'exec "$@"\n',
        encoding="utf-8",
    )
    (shim_dir / "sudo").chmod(0o755)
    return log


def shim_env(log_dir: Path) -> dict[str, str]:
    return {"PATH": f"{log_dir / 'shim'}:{os.environ['PATH']}"}


def test_sudo_routing() -> None:
    """auto routes per record: writable dests direct, unwritable via sudo."""
    # writable dest, auto: no sudo invocation at all
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-sudo-") as tmp:
        root = Path(tmp).resolve()
        log = make_sudo_shim(root)
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")
        manifest = write_manifest(root, [record("dest.conf", plan_src)])

        result = run(["apply", "--sudo", "auto", str(manifest)], env={**shim_env(root), "COMPFUZOR_LINKS_SUDO": "auto"})
        check("auto+writable exits ok", result.returncode, 0)
        check("auto+writable creates the link directly", str(os.readlink(root / "dest.conf")), plan_src)
        sudo_calls = log.read_text(encoding="utf-8").strip() if log.exists() else ""
        check("auto+writable never calls sudo", sudo_calls, "")
        check_absent("auto+writable has no via-sudo note", result.stdout, "via sudo")

    # unwritable parent dir, auto: routing escalates (the shim is not root,
    # so the actual ln fails -- what is asserted is the delegation itself)
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-sudo-") as tmp:
        root = Path(tmp).resolve()
        log = make_sudo_shim(root)
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")
        locked = root / "locked"
        locked.mkdir()
        locked.chmod(0o555)
        manifest = write_manifest(root, [record("locked/dest.conf", plan_src)])

        result = run(["apply", str(manifest)], env=shim_env(root))
        locked.chmod(0o755)  # let TemporaryDirectory clean up
        check("auto+unwritable probes and delegates (shim ln attempted)", "ln" in log.read_text(encoding="utf-8"), True)
        check("auto+unwritable fails without real root", result.returncode, 2)

    # bare --sudo means always: even writable dests route through sudo,
    # the mutation succeeds via the shim, and the row is marked
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-sudo-") as tmp:
        root = Path(tmp).resolve()
        log = make_sudo_shim(root)
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")
        dest = root / "dest.conf"
        dest.write_text("squatter\n", encoding="utf-8")
        manifest = write_manifest(root, [record("dest.conf", plan_src, policy="replace")])

        result = run(["apply", "--sudo", str(manifest)], env=shim_env(root))
        check("bare --sudo exits ok", result.returncode, 0)
        check("bare --sudo routes rm+ln through sudo", "rm" in log.read_text(encoding="utf-8") and "ln" in log.read_text(encoding="utf-8"), True)
        check("bare --sudo creates the link", str(os.readlink(dest)), plan_src)
        check_contains("sudo-mutated row is marked", result.stdout, "via sudo")

    # env=never + unwritable dest: fail loud, never consult sudo
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-sudo-") as tmp:
        root = Path(tmp).resolve()
        log = make_sudo_shim(root)
        src = root / "src"
        src.mkdir()
        (src / "app.conf").write_text("managed\n", encoding="utf-8")
        plan_src = str(src / "app.conf")
        locked = root / "locked"
        locked.mkdir()
        locked.chmod(0o555)
        manifest = write_manifest(root, [record("locked/dest.conf", plan_src)])

        result = run(["apply", str(manifest)], env={**shim_env(root), "COMPFUZOR_LINKS_SUDO": "never"})
        locked.chmod(0o755)
        check("never+unwritable fails", result.returncode > 0, True)
        sudo_calls = log.read_text(encoding="utf-8").strip() if log.exists() else ""
        check("never+unwritable never consults sudo", sudo_calls, "")

    # invalid mode value: usage error
    with tempfile.TemporaryDirectory(prefix="compfuzor-links-sudo-") as tmp:
        root = Path(tmp).resolve()
        manifest = write_manifest(root, [record("dest.conf", "/nowhere/x")])
        result = run(["status", str(manifest)], env={"COMPFUZOR_LINKS_SUDO": "wut"})
        check("invalid COMPFUZOR_LINKS_SUDO is exit 2", result.returncode, 2)


def main() -> None:
    test_human_lines_show_both_sides()
    test_json_carries_structured_reality()
    test_apply_verbs_read_as_verbs()
    test_absent_and_directory()
    test_apply_routes_mutations_through_sudo()
    test_sudo_routing()
    print("all links human-output checks passed")


if __name__ == "__main__":
    main()
