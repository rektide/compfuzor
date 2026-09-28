#!/usr/bin/env python3
"""Exercise the archive library surface (archive/src/index.ts) on disposable fixtures.

Covers what the CLI suite cannot: the public index exports, the flat
compatibility shims, and the structured (no-console) results of the
extracted snapshot/fetch operations. Never touches a real archive.
"""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "repo-jj-archive" / "tests"
TOOLKIT = ROOT / "archive/src/repo-jj-archive.ts"
INDEX = ROOT / "archive/src/index.ts"


def run(*command: str, cwd: Path, check: bool = True) -> str:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    if check and result.returncode:
        raise AssertionError(f"{command} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def create_remote(tmp: Path) -> tuple[Path, Path]:
    remote = tmp / "upstream.git"
    seed = tmp / "seed"
    run("git", "init", "--bare", str(remote), cwd=tmp)
    run("git", "clone", str(remote), str(seed), cwd=tmp)
    run("git", "config", "user.name", "Archive Test", cwd=seed)
    run("git", "config", "user.email", "archive@example.invalid", cwd=seed)
    (seed / "tracked").write_text("original\n")
    run("git", "add", ".", cwd=seed)
    run("git", "commit", "-m", "initial", cwd=seed)
    run("git", "branch", "-M", "main", cwd=seed)
    run("git", "push", "-u", "origin", "main", cwd=seed)
    run("git", "symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
    return remote, seed


def render(archive: Path, remote: Path) -> dict:
    return json.loads(run(
        str(TOOLKIT), "refresh", "--json", "--dest", str(archive), "--repo", str(remote),
        "--remotes", "{}", "--label", "fixture", cwd=archive.parent,
    ))


def node_eval(script: str, cwd: Path) -> str:
    return run("node", "--input-type=module", "-e", script, cwd=cwd)


def import_line(module: Path) -> str:
    literal = json.dumps(str(module))
    return f'await import(await (await import("node:url")).pathToFileURL({literal}).href)'


# Exported index functions and the flat shim each must re-export identically.
EXPORTED_FUNCTIONS = [
    "jj", "lines", "exists", "isDirectory", "refKey", "refs", "revision", "ancestor",
    "preflight", "snapshot", "fetchRemote", "declaredRemotes", "remoteDiff", "mismatchError",
    "reconcile", "refreshArchive", "locateCompfuzor", "harvest", "recoveryCovered",
    "safeLabel", "stamp", "heal",
]
SHIMMED = {"jj": "jj", "preflight": "health", "remoteDiff": "remotes", "refreshArchive": "refresh",
           "harvest": "harvest", "heal": "heal", "locateCompfuzor": "self"}


def test_index_exports_surface_and_flat_shims_reexport_same_bindings() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        script = "const lib = " + import_line(INDEX) + ";\n"
        for binding, module in SHIMMED.items():
            script += (
                f"const flat_{module} = {import_line(ROOT / 'archive/src' / f'{module}.ts')};\n"
            )
        script += "const checks = [\n"
        for binding, module in SHIMMED.items():
            script += f'  ["{binding}", flat_{module}],\n'
        script += (
            "];\n"
            "for (const name of " + json.dumps(EXPORTED_FUNCTIONS) + ")\n"
            '  if (typeof lib[name] !== "function")\n'
            '    throw Error("index does not export function " + name);\n'
            "for (const [name, flat] of checks)\n"
            "  if (lib[name] !== flat[name])\n"
            '    throw Error("shim re-exports a different " + name + " binding");\n'
            "console.log(JSON.stringify({ exports: " + str(len(EXPORTED_FUNCTIONS))
            + ", shims: checks.length }));\n"
        )
        output = json.loads(node_eval(script, tmp))
        assert output == {"exports": len(EXPORTED_FUNCTIONS), "shims": len(SHIMMED)}


def test_snapshot_and_fetch_return_structured_results() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        (archive / "untracked-work").write_text("local edit\n")
        stale_at = run("jj", "--ignore-working-copy", "log", "-r", "@", "-T", "commit_id", cwd=archive)
        script = (
            "const lib = " + import_line(INDEX) + ";\n"
            f"const dest = {json.dumps(str(archive))};\n"
            + """
const snap = await lib.snapshot(dest);
if (snap.dest !== dest || !Array.isArray(snap.conflicts)) throw Error("bad snapshot result");
const fetch = await lib.fetchRemote({ dest, label: "fixture" });
if (fetch.remote !== "origin" || !Array.isArray(fetch.notices)) throw Error("bad fetch result");
const saved = fetch.notices.find((n) => n.kind === "bookmark-created");
if (!saved || !saved.name.startsWith("harvest/fixture/working-copy-"))
  throw Error("fetch did not harvest dirty @: " + JSON.stringify(fetch.notices));
console.log(JSON.stringify({ snapshot: snap, harvest: saved.name }));
"""
        )
        output = json.loads(node_eval(script, tmp))
        assert output["snapshot"] == {"dest": str(archive), "conflicts": []}
        assert run("jj", "--ignore-working-copy", "log", "-r", "@", "-T", "commit_id",
                   cwd=archive) != stale_at, "snapshot did not import the dirty worktree"
        # The harvest bookmark pins exactly the pre-fetch working-copy state.
        assert run("jj", "file", "show", "-r", output["harvest"], "untracked-work",
                   cwd=archive) == "local edit"
        # Unchanged work is already covered: a second fetch mints no duplicate bookmark.
        second = json.loads(node_eval(
            "const lib = " + import_line(INDEX) + ";\n"
            f"const dest = {json.dumps(str(archive))};\n"
            + 'const fetch = await lib.fetchRemote({ dest, label: "fixture" });\n'
            + "console.log(JSON.stringify(fetch));\n", tmp))
        assert second == {"remote": "origin", "notices": []}, second


def test_read_only_preflight_never_mutates_the_checkout() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        head = run("git", "rev-parse", "HEAD", cwd=archive)
        # Dirt that ordinary jj commands would snapshot and import.
        (archive / "pending-edit").write_text("not snapshotted yet\n")
        run("git", "update-ref", "refs/heads/extside", head, cwd=archive)
        op_head = lambda: run("jj", "--ignore-working-copy", "op", "log", "--no-graph", "-n1",
                              "-T", "id", cwd=archive)
        before = op_head()
        probe = json.loads(node_eval(
            "const lib = " + import_line(INDEX) + ";\n"
            f"const dest = {json.dumps(str(archive))};\n"
            + 'const conflicts = await lib.preflight(dest, { readOnly: true });\n'
            + 'console.log(JSON.stringify({ conflicts, bookmarks: [...(await lib.refs(dest, { readOnly: true })).keys()] }));\n',
            tmp))
        assert probe["conflicts"] == [], probe
        # Genuinely read-only: no snapshot, no Git ref import, no new operation.
        assert op_head() == before, "read-only preflight advanced the operation log"
        bookmarks = run("jj", "--ignore-working-copy", "bookmark", "list", "-T", 'name ++ "\\n"',
                        cwd=archive)
        assert "extside" not in bookmarks.split(), "read-only preflight imported a Git ref"
        assert "pending-edit" not in run("jj", "--ignore-working-copy", "diff", "-r", "@",
                                         "--summary", cwd=archive)
        # Control sensitivity: the default (mutating) mode does both.
        node_eval(
            "const lib = " + import_line(INDEX) + ";\n"
            f"const dest = {json.dumps(str(archive))};\n"
            + "await lib.preflight(dest);\n", tmp)
        assert op_head() != before, "test cannot detect mutations from the default mode"
        assert "extside" in run("jj", "--ignore-working-copy", "bookmark", "list", "-T",
                                'name ++ "\\n"', cwd=archive).split()
