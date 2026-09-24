#!/usr/bin/env python3
"""Refresh a canonical archive without using Git's worktree-resetting update path.

Stdout is one JSON result for Ansible; jj diagnostics and failures go to stderr.
Only run this on a checkout whose working tree is not being edited concurrently.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone
from uuid import uuid4


REF_TEMPLATE = (
    'name ++ "\\t" ++ if(remote,remote,"-") ++ "\\t" ++ '
    'if(normal_target,normal_target.commit_id(),"conflict") ++ "\\t" ++ tracked ++ "\\n"'
)
COMMIT_TEMPLATE = (
    'commit_id ++ "\\t" ++ empty ++ "\\t" ++ '
    'parents.map(|c| c.commit_id()).join(",") ++ "\\t" ++ conflict ++ "\\n"'
)
REMOTE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def jj(*args: str, cwd: Path | None = None) -> str:
    command = ["jj", "--no-pager", "--color=never", *args]
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"{' '.join(command)}: {result.stderr.strip()}")
    return result.stdout.strip()


def refs(dest: Path) -> dict[tuple[str, str], tuple[str, bool]]:
    result = {}
    for line in jj("bookmark", "list", "--all-remotes", "-T", REF_TEMPLATE, cwd=dest).splitlines():
        name, remote, target, tracked = line.split("\t")
        result[name, remote] = (target, tracked == "true")
    return result


def revision(dest: Path, rev: str) -> tuple[str, bool, list[str], bool]:
    commit, empty, parents, conflict = jj("log", "-G", "-r", rev, "-T", COMMIT_TEMPLATE, cwd=dest).split("\t")
    return commit, empty == "true", parents.split(",") if parents else [], conflict == "true"


def ancestor(dest: Path, older: str, newer: str) -> bool:
    return int(jj("log", "-r", f"{older}::{newer}", "--count", cwd=dest)) > 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--remotes", required=True, help="JSON mapping of remote names to URLs")
    parser.add_argument("--remote", default="origin")
    parser.add_argument("--version", default="HEAD")
    parser.add_argument("--label", required=True)
    parser.add_argument("--depth", type=int)
    parser.add_argument("--submodules", action="store_true")
    parser.add_argument("--update", choices=("true", "false"), default="true")
    args = parser.parse_args()
    declared = {"origin": args.repo, **json.loads(args.remotes)}
    version = args.version
    selected = args.remote
    if "@" in version and version.rsplit("@", 1)[1] in declared:
        version, selected = version.rsplit("@", 1)
    if selected not in declared:
        raise ValueError(f"selected remote {selected!r} is not declared")
    if not all(REMOTE_NAME.fullmatch(name) and isinstance(url, str) and url for name, url in declared.items()):
        raise ValueError("remote names or URLs are invalid")
    if args.submodules:
        raise ValueError("GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render")
    if args.depth is not None and args.depth < 1:
        raise ValueError("GIT_DEPTH must be positive")
    label = re.sub(r"[^A-Za-z0-9._-]+", "-", args.label).strip(".-") or "deployment"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    notices: list[dict[str, str]] = []
    changed = False
    cloned = False

    def harvest(kind: str, target: str, *, copy: bool = False) -> None:
        nonlocal changed
        if copy:
            # A bookmark on @ itself follows its change ID when the user
            # subsequently edits the worktree. Duplicate under a new change
            # ID so this snapshot cannot drift with future @ rewrites.
            heads = set(jj("log", "-G", "-r", "heads(all())", "-T", 'commit_id ++ "\\n"', cwd=args.dest).splitlines())
            jj("duplicate", "-r", target, cwd=args.dest)
            new_heads = set(jj("log", "-G", "-r", "heads(all())", "-T", 'commit_id ++ "\\n"', cwd=args.dest).splitlines()) - heads
            if len(new_heads) != 1:
                raise RuntimeError(f"expected one duplicated jj snapshot; found {new_heads}")
            target = new_heads.pop()
        name = f"harvest/{label}/{kind}-{stamp}-{uuid4().hex[:8]}"
        jj("bookmark", "create", name, "-r", target, cwd=args.dest)
        notices.append({"kind": "bookmark-created", "name": name, "target": target})
        changed = True

    if not args.dest.exists():
        args.dest.parent.mkdir(parents=True, exist_ok=True)
        command = ["git", "clone", "--colocate", "--remote", selected]
        if args.depth is not None:
            command += ["--depth", str(args.depth)]
        if version != "HEAD":
            command += ["--branch", version]
        jj(*command, declared[selected], str(args.dest), cwd=args.dest.parent)
        notices.append({"kind": "notice", "message": f"cloned jj-colocated archive {args.dest}"})
        changed = True
        cloned = True
    elif not args.dest.is_dir() or not (args.dest / ".git").exists():
        raise ValueError(f"{args.dest} exists but is not a colocated Git checkout; refusing to replace it")
    elif not (args.dest / ".jj").exists():
        jj("git", "init", "--git-repo", str(args.dest / ".git"), str(args.dest), cwd=args.dest)
        notices.append({"kind": "notice", "message": f"adopted existing Git archive into jj: {args.dest}"})
        changed = True

    # This snapshots tracked/untracked changes and imports local Git branches.
    # Do not continue to fetch if jj cannot snapshot the worktree.
    jj("status", cwd=args.dest)
    before = refs(args.dest)
    work, empty, parents, _ = revision(args.dest, "@")

    remote_urls = {}
    for line in jj("git", "remote", "list", cwd=args.dest).splitlines():
        name, _, url = line.partition(" ")
        remote_urls[name] = url
    for name, url in declared.items():
        if name not in remote_urls:
            jj("git", "remote", "add", name, url, cwd=args.dest)
            changed = True
        elif remote_urls[name] != url:
            jj("git", "remote", "set-url", name, url, cwd=args.dest)
            changed = True

    if args.update == "false" and before:
        print(json.dumps({"changed": changed, "notices": notices}))
        return

    # HEAD is the conventional base. Explicit versions select branch bookmarks.
    # For an initial clone, fetch is still necessary for extra remotes/branches.
    # A dirty @ is already a jj commit. Do not mint repeated recovery names
    # for the same revision on consecutive renders without an upstream change.
    if not empty and not any(
        name.startswith(f"harvest/{label}/working-copy-") and remote == "-"
        and revision(args.dest, target)[2] == parents
        and not jj("diff", "--from", target, "--to", "@", "--summary", cwd=args.dest)
        for (name, remote), (target, _) in before.items()
    ):
        harvest("working-copy", work, copy=True)

    # Freeze *all* tracked local refs before fetching: jj's tracked-remote sync
    # otherwise moves them, and a rewritten upstream can abandon the old tip.
    tracked = [(name, remote) for (name, remote), (_, yes) in before.items() if remote not in ("-", "git") and yes]
    for name, remote in tracked:
        jj("bookmark", "untrack", name, "--remote", remote, cwd=args.dest)

    # No prune/abandon of unreachable commits: even rewritten upstream history
    # remains reconstructible while we decide which tips need harvest bookmarks.
    for name in declared:
        jj("--config", "git.abandon-unreachable-commits=false", "git", "fetch", "--remote", name, cwd=args.dest)
    after = refs(args.dest)
    base = version if version != "HEAD" else next(
        (name for name in ("main", "master") if (name, selected) in after), None
    )
    if base is None or (base, selected) not in after:
        raise ValueError(f"remote {selected} does not have branch {version}; specify GIT_VERSION explicitly")
    upstream = after[base, selected][0]
    if upstream == "conflict":
        raise ValueError(f"remote {base}@{selected} is conflicted")
    old_base = before.get((base, "-"), (None, False))[0]
    if old_base == "conflict":
        raise ValueError(f"local bookmark {base} is conflicted; resolve it before updating")

    # Restore ownership of the other local branches: they remain local-only,
    # never moved merely because a remote happened to share their name.
    for (name, remote), (target, _) in before.items():
        if remote != "-" or name == base or target == "conflict":
            continue
        current = after.get((name, "-"))
        if current is None or current[0] != target:
            harvest(f"{name.replace('/', '-')}-local", target)

    if old_base and old_base != upstream and not ancestor(args.dest, old_base, upstream):
        harvest(base.replace("/", "-"), old_base)
    if old_base != upstream:
        jj("bookmark", "set", "-B", "-r", upstream, base, cwd=args.dest)
        if old_base is None:
            notices.append({"kind": "bookmark-created", "name": base, "target": upstream})
        else:
            notices.append({"kind": "notice", "message": f"{base} -> {upstream} ({selected})"})
        changed = True
    elif cloned:
        notices.append({"kind": "bookmark-created", "name": base, "target": upstream})
    jj("bookmark", "track", base, "--remote", selected, cwd=args.dest)

    # Fetch may have changed the current revision only if external Git refs
    # rewrote it; never assume jj's automatic rebase imported the right state.
    current, now_empty, current_parents, _ = revision(args.dest, "@")
    if old_base == current and old_base != upstream and ancestor(args.dest, upstream, current):
        # Local @ was itself the ahead base. Keep it as a fixed, bookmarked
        # parent before the next user edit can rewrite that old base tip.
        jj("new", "@", cwd=args.dest)
        changed = True
    elif not ancestor(args.dest, upstream, current):
        if now_empty and old_base and current_parents == [old_base] and ancestor(args.dest, old_base, upstream):
            jj("rebase", "-r", "@", "-d", base, cwd=args.dest)
        else:
            # Never rewrite a bookmarked dirty @: jj moves bookmarks with a
            # rewritten change. A merge keeps the exact pre-fetch worktree as
            # its first parent, and exposes any conflicts for the operator.
            if empty and current != work:
                harvest("head", work)
            jj("new", "@", base, cwd=args.dest)
        changed = True
        notices.append({"kind": "notice", "message": f"merged local checkout with {base}@{selected}"})
    if revision(args.dest, "@")[3]:
        notices.append({"kind": "notice", "message": "working copy has merge conflicts; resolve them before building"})
    if before.get((base, selected), (None, False))[0] != upstream:
        changed = True
    print(json.dumps({"changed": changed, "notices": notices}))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(f"repo-jj-archive: {error}", file=sys.stderr)
        sys.exit(1)
