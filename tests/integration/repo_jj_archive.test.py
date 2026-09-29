#!/usr/bin/env python3
"""Exercise the archive lane against disposable Git/jj repositories only."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "repo-jj-archive" / "tests"
RUNNER = ROOT / "script" / "repo-jj-archive.ts"
NOOP = {"changed": False, "notices": []}


def run(*command: str, cwd: Path, check: bool = True, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False, env=env)
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


def advance(seed: Path, content: str = "upstream\n") -> str:
    (seed / "tracked").write_text(content)
    run("git", "add", "tracked", cwd=seed)
    run("git", "commit", "-m", "advance", cwd=seed)
    run("git", "push", cwd=seed)
    return run("git", "rev-parse", "HEAD", cwd=seed)


def render(archive: Path, remote: Path, *, update: bool = True, version: str = "HEAD") -> dict:
    return json.loads(run(
        str(RUNNER), "--dest", str(archive), "--repo", str(remote),
        "--remotes", "{}", "--label", "fixture", "--version", version,
        "--update", "true" if update else "false", cwd=archive.parent,
    ))


def toolkit(*args: str, cwd: Path, check: bool = True) -> str:
    return run("node", str(ROOT / "archive/src/repo-jj-archive.ts"), *args, cwd=cwd, check=check)


def intercept_jj(tmp: Path, action: str) -> dict[str, str]:
    """Intercept selected external jj invocations; delegate everything else to real jj."""
    actual = shutil.which("jj")
    assert actual
    bindir = tmp / "bin"
    bindir.mkdir()
    wrapper = bindir / "jj"
    wrapper.write_text(
        "#!/usr/bin/env python3\nimport os, sys\nfrom pathlib import Path\n"
        "args = sys.argv[1:]\n" + action +
        f"\nos.execv({actual!r}, [{actual!r}, *args])\n"
    )
    wrapper.chmod(0o755)
    return os.environ | {"PATH": f"{bindir}{os.pathsep}{os.environ['PATH']}"}


def names(archive: Path) -> list[str]:
    return run("jj", "bookmark", "list", "--all-remotes", "-T", 'name ++ "\\n"', cwd=archive).splitlines()


def test_archive_fast_forward_and_noop() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        first = render(archive, remote)
        assert first["changed"] and (archive / ".jj").is_dir() and (archive / ".git").is_dir()
        assert any(n["kind"] == "bookmark-created" and n["name"] == "main" for n in first["notices"])
        assert render(archive, remote) == NOOP
        new_tip = advance(seed)
        assert render(archive, remote)["changed"]
        assert run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive) == new_tip
        assert (archive / "tracked").read_text() == "upstream\n"
        assert render(archive, remote) == NOOP


def test_archive_harvests_dirty_work_and_divergent_base() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        (archive / "tracked").write_text("local tracked\n")
        (archive / "untracked").write_text("local untracked\n")
        first = render(archive, remote)
        work = next(n for n in first["notices"] if n["kind"] == "bookmark-created")
        assert work["name"].startswith("harvest/fixture/working-copy-")
        assert run("jj", "file", "show", "-r", work["name"], "untracked", cwd=archive) == "local untracked"
        assert render(archive, remote) == NOOP
        (archive / "untracked").write_text("edited later\n")
        later = render(archive, remote)
        assert any(n["kind"] == "bookmark-created" and n["name"] != work["name"] for n in later["notices"])
        assert run("jj", "log", "-G", "-r", work["name"], "-T", "commit_id", cwd=archive) == work["target"]
        assert run("jj", "file", "show", "-r", work["name"], "untracked", cwd=archive) == "local untracked"
        advance(seed)
        merged = render(archive, remote)
        assert merged["changed"] and any("conflicts" in n["message"] for n in merged["notices"])
        assert work["target"] == run("jj", "log", "-G", "-r", work["name"], "-T", "commit_id", cwd=archive)
        assert (archive / "untracked").read_text() == "edited later\n"

    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        # Local main moves ahead, with a separate locally named feature branch.
        run("jj", "new", "main", cwd=archive)
        (archive / "local").write_text("local commit\n")
        run("jj", "describe", "-m", "local progress", cwd=archive)
        run("jj", "bookmark", "set", "main", "-r", "@", cwd=archive)
        run("jj", "bookmark", "create", "feature", "-r", "@", cwd=archive)
        old = run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive)
        advance(seed)
        changed = render(archive, remote)
        base = next(n for n in changed["notices"] if n["kind"] == "bookmark-created" and "/main-" in n["name"])
        assert base["target"] == old
        assert run("jj", "log", "-G", "-r", "feature", "-T", "commit_id", cwd=archive) == old
        assert base["name"].startswith("compfuzor/save/main-")
        assert run("jj", "file", "show", "-r", base["name"], "local", cwd=archive) == "local commit"
        assert not (archive / "local").exists()
        assert run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive) != old
        (archive / "subsequent-work").write_text("new work\n")
        render(archive, remote)
        assert run("jj", "log", "-G", "-r", base["name"], "-T", "commit_id", cwd=archive) == old


def test_archive_adopts_existing_git_without_reset_and_selects_branch() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        run("git", "switch", "-c", "release", cwd=seed)
        (seed / "release-only").write_text("release contents\n")
        run("git", "add", "release-only", cwd=seed)
        run("git", "commit", "-m", "release", cwd=seed)
        run("git", "push", "-u", "origin", "release", cwd=seed)
        archive = tmp / "archive"
        run("git", "clone", "--branch", "release", str(remote), str(archive), cwd=tmp)
        (archive / "not-yet-tracked").write_text("keep me\n")
        result = render(archive, remote, version="release")
        assert (archive / ".jj").is_dir() and (archive / "not-yet-tracked").read_text() == "keep me\n"
        assert "release" in names(archive)
        assert any(n["kind"] == "bookmark-created" and "/working-copy-" in n["name"] for n in result["notices"])


def test_archive_update_bypass_keeps_base_and_resumes() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        before = run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive)
        advance(seed)
        assert render(archive, remote, update=False) == NOOP
        assert run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive) == before
        assert render(archive, remote)["changed"]


def test_deploy_uses_colocated_workspace_without_moving_archive_main() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive" / "fixture"
        workspace = tmp / "deployment" / "repo"
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        first = json.loads(toolkit(*args, cwd=tmp))
        assert first["changed"] and (archive / ".git").is_dir()
        assert (workspace / ".git").is_file() and (workspace / ".jj").is_dir()
        assert run("jj", "workspace", "root", cwd=workspace) == str(workspace)
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP
        archive_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        (archive / "operator-note").write_text("unsnapshotted archive work\n")
        advance(seed)
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert (workspace / "tracked").read_text() == "upstream\n"
        assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive) == archive_at
        assert (archive / "operator-note").read_text() == "unsnapshotted archive work\n"


def test_deploy_replaces_selected_archive_alias_with_dedicated_workspace() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        saved = run("jj", "--ignore-working-copy", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive)
        run("jj", "bookmark", "create", "operator-saved", "-r", "main", cwd=archive)
        (archive / "tracked").write_text("unsnapshotted archive edit\n")
        (archive / "operator-note").write_text("unsnapshotted archive work\n")
        (archive / ".gitignore").write_text(".runtime/\n")
        (archive / ".runtime").mkdir()
        (archive / ".runtime" / "db").write_bytes(b"ignored runtime bytes\n")
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(archive, target_is_directory=True)
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--branch", "main@origin", "--label", "fixture")
        first = json.loads(run(str(RUNNER), *args, cwd=tmp))
        assert first["changed"] and not workspace.is_symlink() and workspace.is_dir()
        assert any("replaced archive symlink" in n.get("message", "") for n in first["notices"])
        assert (workspace / ".git").is_file() and (workspace / ".jj" / "repo").is_file()
        pointer = (workspace / ".jj" / "repo").read_text().strip()
        assert (workspace / ".jj" / pointer).resolve() == (archive / ".jj" / "repo").resolve()
        assert run("jj", "workspace", "root", cwd=workspace) == str(workspace)
        assert run("git", "rev-parse", "--show-toplevel", cwd=workspace) == str(workspace)
        assert (workspace / "tracked").read_text() == "original\n"
        assert (archive / "tracked").read_text() == "unsnapshotted archive edit\n"
        assert (archive / "operator-note").read_text() == "unsnapshotted archive work\n"
        assert (archive / ".runtime" / "db").read_bytes() == b"ignored runtime bytes\n"
        assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "operator-saved", "-T", "commit_id", cwd=archive) == saved
        archive_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP
        advance(seed)
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert (workspace / "tracked").read_text() == "upstream\n"
        assert (archive / "tracked").read_text() == "unsnapshotted archive edit\n"
        assert (archive / "operator-note").read_text() == "unsnapshotted archive work\n"
        assert (archive / ".runtime" / "db").read_bytes() == b"ignored runtime bytes\n"
        assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive) == archive_at


def test_deploy_archive_alias_keeps_link_on_invalid_refresh_options() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        for extra, message in [
            (("--update", "sometimes"), "invalid choice"),
            (("--fetch-scope", "some"), "invalid fetch scope"),
            (("--untrack", "some"), "invalid untrack scope"),
            (("--depth", "0"), "GIT_DEPTH must be positive"),
            (("--submodules",), "requires explicit submodule safety handling"),
        ]:
            workspace.symlink_to("../archive", target_is_directory=True)
            original = workspace.lstat()
            failed = subprocess.run((str(RUNNER), *args, *extra), cwd=tmp,
                                    capture_output=True, text=True)
            assert failed.returncode and failed.stdout == "" and message in failed.stderr
            assert workspace.is_symlink() and workspace.readlink() == Path("../archive")
            assert workspace.lstat().st_ino == original.st_ino
            workspace.unlink()


def test_deploy_archive_alias_keeps_link_when_selected_bookmark_is_conflicted() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        run("jj", "new", "main", cwd=archive)
        (archive / "local").write_text("local progress\n")
        run("jj", "bookmark", "set", "main", "-r", "@", cwd=archive)
        advance(seed)
        conflicted = subprocess.run((str(RUNNER), "refresh", "--json", "--dest", str(archive),
                                     "--repo", str(remote), "--label", "fixture", "--no-save-displaced"),
                                    cwd=tmp, capture_output=True, text=True)
        assert conflicted.returncode and "conflicted after fetch" in conflicted.stderr
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(archive, target_is_directory=True)
        original = workspace.lstat()
        failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                cwd=tmp, capture_output=True, text=True)
        assert failed.returncode and failed.stdout == "" and "local bookmark main is conflicted" in failed.stderr
        assert workspace.is_symlink() and workspace.resolve() == archive
        assert workspace.lstat().st_ino == original.st_ino
        assert (archive / "local").read_text() == "local progress\n"


def test_deploy_archive_alias_keeps_link_when_archive_health_preflight_fails() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        run("jj", "new", "main", cwd=archive)
        (archive / "ghost-only").write_text("missing commit fixture\n")
        run("jj", "status", cwd=archive)
        ghost = run("jj", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        run("jj", "new", "main", cwd=archive)
        # Quarantine a visible jj-only commit object in this disposable fixture.
        loose = archive / ".git" / "objects" / ghost[:2] / ghost[2:]
        assert loose.is_file()
        loose.rename(tmp / "missing-visible-head")
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(archive, target_is_directory=True)
        original = workspace.lstat()
        failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                cwd=tmp, capture_output=True, text=True)
        assert failed.returncode and failed.stdout == "" and ghost in failed.stderr
        assert workspace.is_symlink() and workspace.resolve() == archive
        assert workspace.lstat().st_ino == original.st_ino


def test_deploy_restores_exact_archive_alias_when_creation_fails_without_new_entry() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to("../archive", target_is_directory=True)
        environment = intercept_jj(tmp, """if 'workspace' in args and 'add' in args:
    print('fixture workspace creation failure', file=sys.stderr)
    sys.exit(74)
""")
        failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                cwd=tmp, capture_output=True, text=True, env=environment)
        assert failed.returncode and failed.stdout == "" and "fixture workspace creation failure" in failed.stderr
        assert workspace.is_symlink() and workspace.readlink() == Path("../archive")
        assert workspace.resolve() == archive and (archive / "tracked").read_text() == "original\n"
        assert json.loads(toolkit("deploy", "--json", "--archive", str(archive),
                                  "--workspace", str(workspace), "--repo", str(remote),
                                  "--label", "fixture", cwd=tmp))["changed"]
        assert workspace.is_dir() and not workspace.is_symlink() and (workspace / ".git").is_file()


def test_deploy_archive_alias_uses_canonical_archive_and_parent_identity() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "store" / "fixture"
        archive.parent.mkdir()
        render(archive, remote)
        archive_root = tmp / "archives"
        archive_root.symlink_to(archive.parent, target_is_directory=True)
        selected = tmp / "selected-archive"
        selected.symlink_to(archive_root / "fixture", target_is_directory=True)
        (tmp / "deployment").mkdir()
        parent_alias = tmp / "deployment-alias"
        parent_alias.symlink_to(tmp / "deployment", target_is_directory=True)
        workspace = parent_alias / "repo"
        workspace.symlink_to("../archives/fixture", target_is_directory=True)
        args = ("deploy", "--json", "--archive", str(selected), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert not workspace.is_symlink() and (workspace / ".git").is_file()
        assert selected.is_symlink() and archive_root.is_symlink() and parent_alias.is_symlink()
        assert (archive / "tracked").read_text() == "original\n"
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP


def test_deploy_archive_alias_selects_declared_branch_remote_without_switching_archive() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        run("git", "switch", "-c", "release", cwd=seed)
        (seed / "tracked").write_text("release deployment\n")
        run("git", "commit", "-am", "release", cwd=seed)
        run("git", "push", "-u", "origin", "release", cwd=seed)
        archive = tmp / "archive"
        remotes = json.dumps({"peer": str(remote)})
        toolkit("refresh", "--dest", str(archive), "--repo", str(remote),
                "--remotes", remotes, "--label", "fixture", cwd=tmp)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(archive, target_is_directory=True)
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--remotes", remotes, "--branch", "release@peer", "--label", "fixture")
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert (workspace / "tracked").read_text() == "release deployment\n"
        assert (archive / "tracked").read_text() == "original\n"
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP


def test_deploy_refuses_unrelated_and_dangling_workspace_links_untouched() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        unrelated = tmp / "other-archive"
        render(unrelated, remote)
        (unrelated / "operator-note").write_text("unrelated local work\n")
        child = tmp / "child-workspace"
        toolkit("deploy", "--archive", str(archive), "--workspace", str(child),
                "--repo", str(remote), "--label", "fixture", cwd=tmp)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        for target in (unrelated, child, tmp / "missing"):
            workspace.symlink_to(target, target_is_directory=True)
            original = workspace.lstat()
            failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                     "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                    cwd=tmp, capture_output=True, text=True)
            assert failed.returncode and failed.stdout == "" and "is occupied" in failed.stderr
            assert workspace.is_symlink() and workspace.readlink() == target
            assert workspace.lstat().st_ino == original.st_ino
            workspace.unlink()
        assert (unrelated / "operator-note").read_text() == "unrelated local work\n"
        assert (child / ".git").is_file() and not (tmp / "missing").exists()


def test_deploy_archive_alias_keeps_link_on_failed_remote_or_branch_preflight() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        (archive / "operator-note").write_text("still unsnapshotted\n")
        archive_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        for declared, extra, message in [
            (remote, ("--branch", "absent"), "absent@origin is unavailable"),
            (remote, ("--remote", "absent"), "selected remote 'absent' is not declared"),
            (remote, ("--remotes", "[]"), "--remotes must be a JSON object"),
            (remote, ("--remotes", '{"peer":""}'), "remote names or URLs are invalid"),
            (tmp / "other.git", (), "declared remote URL mismatch"),
        ]:
            workspace.symlink_to(archive, target_is_directory=True)
            original = workspace.lstat()
            failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                     "--workspace", str(workspace), "--repo", str(declared),
                                     "--label", "fixture", *extra),
                                    cwd=tmp, capture_output=True, text=True)
            assert failed.returncode and failed.stdout == "" and message in failed.stderr
            assert workspace.is_symlink() and workspace.resolve() == archive
            assert workspace.lstat().st_ino == original.st_ino
            assert (archive / "operator-note").read_text() == "still unsnapshotted\n"
            assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive) == archive_at
            workspace.unlink()


def test_deploy_archive_alias_refuses_lexical_and_canonical_nesting() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        parent_alias = tmp / "parent-alias"
        parent_alias.symlink_to(archive, target_is_directory=True)
        outside = tmp / "outside"
        outside.mkdir()
        (archive / "outward-parent").symlink_to(outside, target_is_directory=True)
        for workspace in (archive / "repo", parent_alias / "repo", archive / "outward-parent" / "repo"):
            workspace.symlink_to(archive, target_is_directory=True)
            original = workspace.lstat()
            failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                     "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                    cwd=tmp, capture_output=True, text=True)
            assert failed.returncode and failed.stdout == "" and "non-nested" in failed.stderr
            assert workspace.is_symlink() and workspace.resolve() == archive
            assert workspace.lstat().st_ino == original.st_ino
            workspace.unlink()
        assert (archive / "tracked").read_text() == "original\n"


def test_deploy_archive_alias_rechecks_changed_link_before_unlinking() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(archive, target_is_directory=True)
        unrelated = tmp / "unrelated"
        unrelated.mkdir()
        (unrelated / "sentinel").write_text("do not touch\n")
        environment = intercept_jj(tmp, f"""if args[-3:] == ['git', 'remote', 'list']:
    link = Path({str(workspace)!r})
    link.unlink()
    link.symlink_to({str(unrelated)!r}, target_is_directory=True)
""")
        failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                cwd=tmp, capture_output=True, text=True, env=environment)
        assert failed.returncode and failed.stdout == "" and "changed since archive symlink admission" in failed.stderr
        assert workspace.is_symlink() and workspace.resolve() == unrelated
        assert (unrelated / "sentinel").read_text() == "do not touch\n"
        assert (archive / "tracked").read_text() == "original\n"


def test_deploy_archive_alias_does_not_delete_partial_creation_state() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(archive, target_is_directory=True)
        environment = intercept_jj(tmp, """if 'workspace' in args and 'add' in args:
    destination = Path(args[-1])
    destination.mkdir()
    (destination / 'partial-state').write_text('retain for investigation\\n')
    print('fixture partial workspace creation failure', file=sys.stderr)
    sys.exit(74)
""")
        failed = subprocess.run((str(RUNNER), "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(workspace), "--repo", str(remote), "--label", "fixture"),
                                cwd=tmp, capture_output=True, text=True, env=environment)
        assert failed.returncode and failed.stdout == "" and "fixture partial workspace creation failure" in failed.stderr
        assert workspace.is_dir() and not workspace.is_symlink()
        assert (workspace / "partial-state").read_text() == "retain for investigation\n"
        assert (archive / "tracked").read_text() == "original\n"


def test_deploy_accepts_symlinked_archive_but_refuses_dangling_link() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "store" / "fixture"
        archive.parent.mkdir()
        render(archive, remote)
        linked = tmp / "archive" / "fixture"
        linked.parent.mkdir()
        linked.symlink_to(archive, target_is_directory=True)
        workspace = tmp / "deployment" / "repo"
        args = ("deploy", "--json", "--archive", str(linked), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        first = json.loads(toolkit(*args, cwd=tmp))
        assert first["changed"] and (workspace / ".git").is_file() and (workspace / ".jj").is_dir()
        assert run("jj", "workspace", "root", cwd=workspace) == str(workspace)
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP
        advance(seed)
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert (workspace / "tracked").read_text() == "upstream\n"
        dangling = tmp / "dangling" / "fixture"
        dangling.parent.mkdir()
        dangling.symlink_to(tmp / "store" / "absent")
        broken = subprocess.run(
            ("node", str(ROOT / "archive/src/repo-jj-archive.ts"), "deploy", "--json",
             "--archive", str(dangling), "--workspace", str(tmp / "nowhere" / "repo"),
             "--repo", str(remote), "--label", "fixture"),
            cwd=tmp, capture_output=True, text=True)
        assert broken.returncode and "not a jj-colocated archive" in broken.stderr
        assert not (tmp / "nowhere").exists()


def test_deploy_adds_git_worktree_to_existing_archive_jj_workspace() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        workspace = tmp / "deployment" / "repo"
        render(archive, remote)
        workspace.parent.mkdir()
        run("jj", "workspace", "add", "--no-colocate", "--name", "fixture-deployment",
            "--revision", "main@origin", str(workspace), cwd=archive)
        assert (workspace / ".jj").is_dir() and not (workspace / ".git").exists()
        (workspace / "local-note").write_text("uncommitted local work\n")
        (workspace / ".gitignore").write_text(".runtime/\n")
        (workspace / ".runtime").mkdir()
        (workspace / ".runtime" / "db").write_bytes(b"ignored runtime bytes\n")
        (archive / "archive-note").write_text("unsnapshotted archive work\n")
        archive_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        (workspace / ".git").write_text("occupied Git metadata\n")
        refused = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"), *args),
                                 cwd=tmp, capture_output=True, text=True)
        assert refused.returncode and (workspace / ".git").read_text() == "occupied Git metadata\n"
        (workspace / ".git").unlink()
        result = json.loads(run("node", str(ROOT / "archive/repo-jj-archive.ts"), *args, cwd=tmp))
        assert result["changed"] and any("added Git worktree" in n.get("message", "")
                                         for n in result["notices"])
        assert (workspace / ".git").is_file()
        assert run("git", "rev-parse", "--show-toplevel", cwd=workspace) == str(workspace)
        assert run("git", "check-ignore", ".runtime/db", cwd=workspace) == ".runtime/db"
        assert (workspace / "local-note").read_text() == "uncommitted local work\n"
        assert (workspace / ".runtime" / "db").read_bytes() == b"ignored runtime bytes\n"
        assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive) == archive_at
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP
        advance(seed)
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert (workspace / "tracked").read_text() == "upstream\n"
        assert (workspace / "local-note").read_text() == "uncommitted local work\n"
        assert (workspace / ".runtime" / "db").read_bytes() == b"ignored runtime bytes\n"
        assert (archive / "archive-note").read_text() == "unsnapshotted archive work\n"


def test_deploy_refuses_unrelated_jj_repo_without_git_worktree() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        workspace = tmp / "unrelated"
        render(archive, remote)
        run("jj", "git", "clone", "--no-colocate", str(remote), str(workspace), cwd=tmp)
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        output = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"), *args),
                                cwd=tmp, capture_output=True, text=True)
        assert output.returncode and "not a verified jj workspace" in output.stderr
        assert not (workspace / ".git").exists()
        assert (workspace / ".jj").is_dir()


def test_adding_another_workspace_snapshots_archive_once_then_refreshes_leave_it_alone() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        first = tmp / "first" / "repo"
        second = tmp / "second" / "repo"
        def deploy(path: Path) -> dict:
            return json.loads(toolkit("deploy", "--json", "--archive", str(archive),
                                      "--workspace", str(path), "--repo", str(remote),
                                      "--label", "fixture", cwd=tmp))
        deploy(first)
        original_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        (archive / "unsnapshotted").write_text("operator work\n")
        deploy(second)
        snapped_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        assert snapped_at != original_at
        assert run("jj", "file", "show", "-r", "@", "unsnapshotted", cwd=archive) == "operator work"
        advance(seed)
        deploy(first)
        deploy(second)
        assert (archive / "unsnapshotted").read_text() == "operator work\n"
        assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive) == snapped_at


def test_explicit_remote_update_keeps_nonconflicting_workspace_edits() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        workspace = tmp / "deployment" / "repo"
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--branch", "main@origin", "--label", "fixture")
        toolkit(*args, cwd=tmp)
        (workspace / "local-note").write_text("in progress\n")
        advance(seed)
        assert json.loads(toolkit(*args, cwd=tmp))["changed"]
        assert (workspace / "tracked").read_text() == "upstream\n"
        assert (workspace / "local-note").read_text() == "in progress\n"


def test_deploy_saves_diverged_branch_without_moving_archive_main_workspace() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        workspace = tmp / "deployment" / "repo"
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        toolkit(*args, cwd=tmp)
        run("jj", "new", "main", cwd=archive)
        (archive / "archive-progress").write_text("work on archive main\n")
        run("jj", "describe", "-m", "local progress", cwd=archive)
        run("jj", "bookmark", "set", "main", "-r", "@", cwd=archive)
        archive_at = run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        (archive / "unsnapshotted").write_text("operator state\n")
        advance(seed)
        result = json.loads(toolkit(*args, cwd=tmp))
        saved = [n for n in result["notices"] if n.get("name", "").startswith("compfuzor/save/main-")]
        assert len(saved) == 1 and saved[0]["target"] == archive_at
        assert run("jj", "--ignore-working-copy", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive) == archive_at
        assert (archive / "unsnapshotted").read_text() == "operator state\n"
        assert (archive / "archive-progress").read_text() == "work on archive main\n"
        assert (workspace / "tracked").read_text() == "upstream\n"


def test_deploy_refuses_occupied_checkout_without_changing_archive() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        workspace = tmp / "deployment" / "repo"
        workspace.mkdir(parents=True)
        (workspace / ".gitignore").write_text("runtime\n")
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        result = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"), *args),
                                cwd=tmp, capture_output=True, text=True)
        assert result.returncode and "is occupied" in result.stderr and result.stdout == ""
        assert not archive.exists() and (workspace / ".gitignore").read_text() == "runtime\n"
        (workspace / ".gitignore").unlink()
        run("git", "clone", str(remote), str(workspace), cwd=tmp)
        (workspace / "tracked").write_text("local changes\n")
        run("git", "switch", "-c", "local-feature", cwd=workspace)
        result = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"), *args),
                                cwd=tmp, capture_output=True, text=True)
        assert result.returncode and "is occupied" in result.stderr
        assert not archive.exists() and not (workspace / ".jj").exists()
        assert run("git", "branch", "--show-current", cwd=workspace) == "local-feature"
        assert (workspace / "tracked").read_text() == "local changes\n"


def test_deploy_refuses_nested_or_aliased_paths_before_clone() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        outer = tmp / "outer"
        archive = outer / "archive"
        nested = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"),
                                 "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(outer), "--repo", str(remote),
                                 "--label", "fixture"), cwd=tmp, capture_output=True, text=True)
        assert nested.returncode and "non-nested" in nested.stderr and not outer.exists()

        outer.mkdir()
        render(archive, remote)
        alias = tmp / "alias"
        alias.symlink_to(archive, target_is_directory=True)
        nested = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"),
                                 "deploy", "--json", "--archive", str(archive),
                                 "--workspace", str(alias / "nested"), "--repo", str(remote),
                                 "--label", "fixture"), cwd=tmp, capture_output=True, text=True)
        assert nested.returncode and "non-nested" in nested.stderr
        assert not (archive / "nested").exists()


def test_refresh_fetches_all_without_untracking_and_saves_only_divergence() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        run("git", "switch", "-c", "feature", cwd=seed)
        (seed / "feature").write_text("upstream feature\n")
        run("git", "add", "feature", cwd=seed)
        run("git", "commit", "-m", "feature", cwd=seed)
        run("git", "push", "-u", "origin", "feature", cwd=seed)
        run("git", "switch", "main", cwd=seed)
        archive = tmp / "archive"
        workspace = tmp / "deployment" / "repo"
        args = ("deploy", "--json", "--archive", str(archive), "--workspace", str(workspace),
                "--repo", str(remote), "--branch", "main", "--label", "fixture")
        toolkit(*args, cwd=tmp)
        run("jj", "bookmark", "track", "feature@origin", cwd=workspace)
        feature_before = run("jj", "log", "-G", "-r", "feature", "-T", "commit_id", cwd=workspace)
        (seed / "tracked").write_text("new main\n")
        run("git", "add", "tracked", cwd=seed)
        run("git", "commit", "-m", "main update", cwd=seed)
        run("git", "push", "origin", "main", cwd=seed)
        result = json.loads(toolkit(*args, cwd=tmp))
        assert result["changed"] and not any(n["name"].startswith("compfuzor/save/")
                                             for n in result["notices"] if "name" in n)
        assert run("jj", "bookmark", "list", "--tracked", "feature", cwd=workspace).startswith("feature")
        assert run("jj", "log", "-G", "-r", "feature", "-T", "commit_id", cwd=workspace) == feature_before

        # Local feature and upstream feature each advance from the same base.
        run("jj", "new", "feature", cwd=workspace)
        (workspace / "local-feature").write_text("local work\n")
        run("jj", "bookmark", "set", "feature", "-r", "@", cwd=workspace)
        local_tip = run("jj", "log", "-G", "-r", "feature", "-T", "commit_id", cwd=workspace)
        run("git", "switch", "feature", cwd=seed)
        (seed / "feature").write_text("rewritten by upstream\n")
        run("git", "add", "feature", cwd=seed)
        run("git", "commit", "-m", "feature update", cwd=seed)
        run("git", "push", "origin", "feature", cwd=seed)
        result = json.loads(toolkit(*args, cwd=tmp))
        saved = [n for n in result["notices"] if n.get("name", "").startswith("compfuzor/save/feature-")]
        assert len(saved) == 1 and saved[0]["target"] == local_tip
        assert run("jj", "bookmark", "list", "--tracked", "feature", cwd=workspace).startswith("feature")
        assert run("jj", "log", "-G", "-r", "feature", "-T", "commit_id", cwd=workspace) == run(
            "git", "rev-parse", "HEAD", cwd=seed)
        assert run("jj", "file", "show", "-r", saved[0]["name"], "local-feature", cwd=workspace) == "local work"


def test_fetching_only_a_new_unrelated_branch_reports_changed() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        run("git", "switch", "-c", "feature", cwd=seed)
        (seed / "feature").write_text("new branch\n")
        run("git", "add", "feature", cwd=seed)
        run("git", "commit", "-m", "feature", cwd=seed)
        run("git", "push", "-u", "origin", "feature", cwd=seed)
        assert render(archive, remote)["changed"]
        assert "feature" in names(archive)
        assert render(archive, remote) == NOOP


def test_refresh_without_save_leaves_diverged_bookmark_conflicted() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        run("jj", "new", "main", cwd=archive)
        (archive / "local").write_text("local\n")
        run("jj", "bookmark", "set", "main", "-r", "@", cwd=archive)
        old_tip = run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive)
        advance(seed)
        result = subprocess.run(("node", str(ROOT / "archive/src/repo-jj-archive.ts"),
                                 "refresh", "--json", "--dest", str(archive), "--repo", str(remote),
                                 "--label", "fixture", "--no-save-displaced"), cwd=tmp,
                                capture_output=True, text=True)
        assert result.returncode and result.stdout == "" and "conflicted after fetch" in result.stderr
        assert "main" in run("jj", "bookmark", "list", "--conflicted", cwd=archive)
        assert run("jj", "log", "-G", "-r", old_tip, "-T", "commit_id", cwd=archive) == old_tip


def test_selected_fetch_leaves_other_branch_untouched_and_remote_rewrite_follows_upstream() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        (seed / "tracked").write_text("first upstream change\n")
        run("git", "commit", "-am", "first upstream change", cwd=seed)
        run("git", "push", "origin", "main", cwd=seed)
        archive = tmp / "archive"
        render(archive, remote)
        old_tip = run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive)
        run("git", "reset", "--hard", "HEAD~1", cwd=seed)
        (seed / "tracked").write_text("rewritten upstream change\n")
        run("git", "commit", "-am", "replacement", cwd=seed)
        run("git", "push", "--force", "origin", "main", cwd=seed)
        run("git", "switch", "-c", "other", cwd=seed)
        (seed / "other").write_text("not selected\n")
        run("git", "add", "other", cwd=seed)
        run("git", "commit", "-m", "other branch", cwd=seed)
        run("git", "push", "-u", "origin", "other", cwd=seed)
        run("git", "switch", "main", cwd=seed)
        args = ("refresh", "--json", "--dest", str(archive), "--repo", str(remote),
                "--label", "fixture", "--fetch-scope", "selected")
        notices = json.loads(toolkit(*args, cwd=tmp))["notices"]
        assert not any(n.get("name", "").startswith("compfuzor/save/") for n in notices)
        assert run("jj", "log", "-G", "-r", "main", "-T", "commit_id", cwd=archive) == run(
            "git", "rev-parse", "HEAD", cwd=seed)
        assert old_tip != run("git", "rev-parse", "HEAD", cwd=seed)
        assert "other" not in names(archive)


def test_ansible_accumulates_bookmark_notices_at_play_end() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        playbook = tmp / "render.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    NAME: fixture
    DIR: {str(tmp / 'deployment')!r}
    REPO: {str(remote)!r}
    GIT_DIR: {str(tmp / 'deployment' / 'repo')!r}
    ARCHIVE_SRC: {str(archive)!r}
    COMPFUZOR_REPO_JJ_RUNNER: {str(RUNNER)!r}
  tasks:
    - import_role:
        name: compfuzor_repo_notices
    - import_tasks: {str(ROOT / 'tasks/compfuzor/repo_jj_archive.tasks')!r}
    - name: proof handler prints after other tasks
      debug:
        msg: end-of-play-task
""")
        environment = os.environ | {
            "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"),
            "ANSIBLE_ROLES_PATH": str(ROOT / "roles"),
        }
        output = run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                     cwd=ROOT, env=environment)
        assert "end-of-play-task" in output and "BOOKMARK CREATED  main ->" in output, output
        assert output.index("end-of-play-task") < output.index("BOOKMARK CREATED  main ->")
        assert "REPO NOTICE" in output
        assert "BOOKMARK CREATED" not in run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                                              cwd=ROOT, env=environment)


def test_full_includes_route_primary_to_archive_workspace() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        # Auxiliary REPOS are independent deployment-local Git clones even
        # when the primary REPO uses the jj archive lane.
        aux_dir = tmp / "auxiliary"
        aux_dir.mkdir()
        auxiliary, _ = create_remote(aux_dir)
        archive = tmp / "archive" / "fixture"
        deployed = tmp / "fixture"
        (tmp / "vars").symlink_to(ROOT / "vars", target_is_directory=True)
        (tmp / "files").symlink_to(ROOT / "files", target_is_directory=True)
        playbook = tmp / "full-render.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: opt
    type: opt
    NAME: fixture
    INSTANCE: main
    DIR: {str(deployed)!r}
    ETC: {str(deployed / 'etc')!r}
    HOMEDIR: {str(tmp / 'home')!r}
    ARCHIVE_SRC: {str(archive)!r}
    REPO: {str(remote)!r}
    REPOS: {{aux: {str(auxiliary)!r}}}
    ARCHIVE_DOWNLOAD: true
    COMPFUZOR_REPO_JJ_RUNNER: {str(RUNNER)!r}
    PKGS_BYPASS: true
    APT_BYPASS: true
    BINS_BYPASS: true
    BINS_RUN_BYPASS: true
    DIR_BYPASS: true
    FS_BYPASS: true
    ENV_BYPASS: true
    LINKS_BYPASS: true
    SYSTEMD_THUNK_BYPASS: true
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor.includes')!r}
""")
        environment = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"),
                                    "ANSIBLE_ROLES_PATH": str(ROOT / "roles")}
        output = run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), cwd=ROOT,
                     env=environment)
        assert (archive / ".jj").is_dir() and (deployed / "repo" / ".jj").is_dir(), output
        assert not (deployed / "repo").is_symlink() and (deployed / "repo" / ".git").is_file()
        assert (deployed / "aux" / ".git").is_dir() and not (deployed / "aux" / ".jj").exists()
        assert "BOOKMARK CREATED  main ->" in output
        git_task = output.split("TASK [Compfuzor: fetch git repositories]", 1)[1].split("TASK [", 1)[0]
        assert str(deployed / "aux") in git_task and str(archive) not in git_task


def test_nonarchive_git_checkout_updates_by_default_without_custom_guard() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        deployment = tmp / "deployment"
        deployment.mkdir()
        checkout = deployment / "checkout"
        playbook = tmp / "git-render.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    REPO: {str(remote)!r}
    REPO_DIR: {str(checkout)!r}
    GIT_DIR: {str(checkout)!r}
    DIR: {str(deployment)!r}
    OWNER: {os.getuid()}
    GROUP: {os.getgid()}
    ARCHIVE_DOWNLOAD: false
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor/repo_git.tasks')!r}
""")
        environment = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        command = ("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook))
        run(*command, cwd=ROOT, env=environment)
        assert (checkout / ".git").is_dir() and not (checkout / ".jj").exists()
        advance(seed)
        run(*command, cwd=ROOT, env=environment)
        assert (checkout / "tracked").read_text() == "upstream\n"


def test_custom_workspace_exposure_never_replaces_an_old_archive_link() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        deployment = tmp / "deployment"
        deployment.mkdir()
        workspace = tmp / "custom-workspace"
        workspace.mkdir()
        archive = tmp / "archive"
        archive.mkdir()
        link = deployment / "repo"
        link.symlink_to(archive)
        playbook = tmp / "exposure.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(deployment)!r}
    REPO_LINK_DIR: repo
    REPO: example.invalid/repo
    ARCHIVE_DOWNLOAD: true
    GIT_DIR: {str(workspace)!r}
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor/fs_repo.tasks')!r}
""")
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        output = run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                     cwd=ROOT, env=env, check=False)
        assert "is occupied" in output and link.resolve() == archive
        link.unlink()
        run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), cwd=ROOT, env=env)
        assert link.is_symlink() and link.resolve() == workspace


def test_archive_failure_reports_runner_error_not_json_parse_error() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        destination = tmp / "occupied-non-repo"
        destination.mkdir()
        (destination / ".hidden").write_text("do not erase\n")
        playbook = tmp / "failure.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(tmp)!r}
    NAME: fixture
    REPO: {str(remote)!r}
    GIT_DIR: {str(destination)!r}
    ARCHIVE_SRC: {str(tmp / 'archive')!r}
    COMPFUZOR_REPO_JJ_RUNNER: {str(RUNNER)!r}
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor/repo_jj_archive.tasks')!r}
""")
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        output = run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                     cwd=ROOT, env=env, check=False)
        assert "is occupied" in output and "from_json" not in output


def test_cli_and_legacy_refresh_have_the_same_json_contract() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        legacy = render(archive, remote)
        args = ("--dest", str(archive), "--repo", str(remote),
                "--remotes", "{}", "--label", "fixture")
        assert json.loads(toolkit("refresh", "--json", *args, cwd=tmp)) == NOOP
        assert json.loads(toolkit(*args, cwd=tmp)) == NOOP
        assert legacy["changed"] and toolkit("refresh", "--help", cwd=tmp).count("--json") == 1
        invalid = subprocess.run((str(RUNNER), "refresh", "--json", "--repo", str(remote),
                                  "--label", "fixture"), cwd=tmp, capture_output=True, text=True)
        assert invalid.returncode and invalid.stdout == "" and "--dest" in invalid.stderr


def test_remote_mismatch_fails_loudly_then_reconciles_deliberately() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        original, _ = create_remote(tmp)
        # URL mismatch need not point at a real remote until explicitly reconciled.
        archive = tmp / "archive"
        render(archive, original)
        declared = str(tmp / "replacement.git")
        args = ("--dest", str(archive), "--repo", declared,
                "--remotes", "{}", "--label", "fixture", "--update", "false")
        result = subprocess.run((str(RUNNER), "refresh", "--json", *args), cwd=tmp,
                                capture_output=True, text=True)
        assert result.returncode and result.stdout == ""
        assert str(original) in result.stderr and declared in result.stderr
        assert "remotes --dest" in result.stderr and "--reconcile" in result.stderr
        assert run("jj", "git", "remote", "list", cwd=archive) == f"origin {original}"
        assert "Reconciled origin" in toolkit("remotes", "--dest", str(archive),
                                              "--repo", declared, "--reconcile", cwd=tmp)
        assert run("jj", "git", "remote", "list", cwd=archive) == f"origin {declared}"
        assert json.loads(toolkit("refresh", "--json", *args, cwd=tmp)) == NOOP
        # Missing additional remotes are also proposed, not silently forgotten.
        missing = subprocess.run((str(RUNNER), "remotes", "--dest", str(archive), "--repo",
                                  declared, "--remotes", '{"peer":"other"}'), cwd=tmp,
                                 capture_output=True, text=True)
        assert missing.returncode and 'peer\t"other"\t"(missing)"' in missing.stderr


def test_ghost_head_preflight_and_explicit_re_adopt() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, remote)
        run("jj", "new", "main", cwd=archive)
        (archive / "ghost-only").write_text("discarded by Git maintenance\n")
        run("jj", "status", cwd=archive)
        ghost = run("jj", "log", "-G", "-r", "@", "-T", "commit_id", cwd=archive)
        run("jj", "new", "main", cwd=archive)
        # Simulate a git repack pruning a *bare jj view head* with no Git ref.
        # Quarantine the loose object only inside the disposable fixture.
        loose = archive / ".git" / "objects" / ghost[:2] / ghost[2:]
        assert loose.is_file() and ghost in run("jj", "log", "-G", "-r", "visible_heads()",
                                                  "-T", "commit_id", cwd=archive)
        for ref in run("git", "for-each-ref", "--format=%(refname) %(objectname)",
                       "refs/jj/keep", cwd=archive).splitlines():
            name, target = ref.split()
            if target == ghost:
                run("git", "update-ref", "-d", name, cwd=archive)
        loose.rename(tmp / "pruned-commit-object")
        result = subprocess.run((str(RUNNER), "refresh", "--json", "--dest", str(archive),
                                 "--repo", str(remote), "--remotes", "{}", "--label", "fixture"),
                                cwd=tmp, capture_output=True, text=True)
        assert result.returncode and result.stdout == ""
        assert ghost in result.stderr and "ghost commit" in result.stderr
        assert "heal --dest" in result.stderr and "Object " not in result.stderr
        refused = subprocess.run((str(RUNNER), "heal", "--dest", str(archive)), cwd=tmp,
                                 capture_output=True, text=True)
        assert refused.returncode and "--yes" in refused.stderr and (archive / ".jj").is_dir()
        message = toolkit("heal", "--dest", str(archive), "--yes", cwd=tmp)
        backup = next(archive.glob(".jj.broken-ghost-*"))
        assert str(backup) in message and backup.is_dir() and (archive / ".jj").is_dir()
        assert "Visible heads OK" in toolkit("health", "--dest", str(archive), cwd=tmp)
        assert json.loads(toolkit("refresh", "--json", "--dest", str(archive),
                                  "--repo", str(remote), "--label", "fixture", cwd=tmp)) == NOOP


def test_ansible_remote_fix_requires_opt_in() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        original, _ = create_remote(tmp)
        archive = tmp / "archive"
        render(archive, original)
        replacement = tmp / "alternate.git"
        run("git", "clone", "--bare", str(original), str(replacement), cwd=tmp)
        playbook = tmp / "remote-fix.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    NAME: fixture
    DIR: {str(tmp)!r}
    REPO: {str(replacement)!r}
    GIT_DIR: {str(tmp / 'deployment' / 'repo')!r}
    ARCHIVE_SRC: {str(archive)!r}
    COMPFUZOR_REPO_JJ_RUNNER: {str(RUNNER)!r}
  tasks:
    - import_role:
        name: compfuzor_repo_notices
    - import_tasks: {str(ROOT / 'tasks/compfuzor/repo_jj_archive.tasks')!r}
""")
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"),
                            "ANSIBLE_ROLES_PATH": str(ROOT / "roles")}
        cmd = ("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook))
        failed = run(*cmd, cwd=ROOT, env=env, check=False)
        assert "declared remote URL mismatch" in failed and "from_json" not in failed
        assert run("jj", "git", "remote", "list", cwd=archive) == f"origin {original}"
        run(*cmd, "-e", "GIT_REMOTE_FIX=true", cwd=ROOT, env=env)
        assert run("jj", "git", "remote", "list", cwd=archive) == f"origin {replacement}"


def test_fine_grained_commands_and_opt_in_checkout_detection() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        archive = tmp / "archive" / "rektide" / "compfuzor"
        archive.parent.mkdir(parents=True)
        render(archive, remote)
        assert str(archive) in toolkit("self", "--archive-dir", str(tmp / "archive"), cwd=tmp)
        assert "Visible heads OK" in toolkit("health", "--dest", str(archive), cwd=tmp)
        (archive / "local-note").write_text("kept\n")
        assert "Snapshotted" in toolkit("snapshot", "--dest", str(archive), cwd=tmp)
        fetched = toolkit("fetch", "--dest", str(archive), "--label", "fixture", cwd=tmp)
        assert "BOOKMARK CREATED  harvest/fixture/working-copy-" in fetched
        assert "Fetched origin" in fetched
        assert "(origin fetched)" in toolkit("self", "--archive-dir", str(tmp / "archive"),
                                              "--freshen", cwd=tmp)
        assert "No compfuzor archive" in toolkit("self", "--archive-dir", str(tmp / "absent"), cwd=tmp)


def test_launcher_uses_standalone_bundle_without_source_or_node_modules() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        (tmp / "script").mkdir()
        (tmp / "archive").mkdir()
        launcher = tmp / "script/repo-jj-archive.ts"
        shutil.copy2(RUNNER, launcher)
        shutil.copy2(ROOT / "archive/repo-jj-archive.ts", tmp / "archive/repo-jj-archive.ts")
        # Source in a slim deployment without pnpm install must not mask the bundle.
        (tmp / "archive/src").mkdir()
        (tmp / "archive/src/repo-jj-archive.ts").write_text("throw Error('unbundled import attempted')\n")
        remote, _ = create_remote(tmp)
        checkout = tmp / "checkout"
        output = run(str(launcher), "refresh", "--json", "--dest", str(checkout),
                     "--repo", str(remote), "--label", "fixture", cwd=tmp)
        assert json.loads(output)["changed"] and (checkout / ".jj").is_dir()
        workspace = tmp / "deployment" / "repo"
        workspace.parent.mkdir()
        workspace.symlink_to(checkout, target_is_directory=True)
        (checkout / "operator-note").write_text("bundle must keep archive work\n")
        args = ("deploy", "--json", "--archive", str(checkout), "--workspace", str(workspace),
                "--repo", str(remote), "--label", "fixture")
        first = json.loads(run(str(launcher), *args, cwd=tmp))
        assert first["changed"] and any("replaced archive symlink" in n.get("message", "")
                                         for n in first["notices"])
        assert not workspace.is_symlink() and (workspace / ".jj" / "repo").is_file()
        assert (workspace / ".git").is_file()
        assert (checkout / "operator-note").read_text() == "bundle must keep archive work\n"
        assert json.loads(run(str(launcher), *args, cwd=tmp)) == NOOP


def test_runner_prefers_host_checkout_with_playbook_fallback() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, seed = create_remote(tmp)
        archive = tmp / "archive"
        # Host compfuzor checkout in the canonical rektide/compfuzor shape;
        # its launcher is a wrapper that records use, then execs the real
        # committed bundle so the refresh itself behaves identically.
        hostcf = tmp / "archive-root" / "rektide" / "compfuzor"
        run("git", "clone", str(remote), str(hostcf), cwd=tmp)
        run("jj", "git", "init", "--colocate", cwd=hostcf)
        (hostcf / "script").mkdir(parents=True)
        marker = tmp / "host-runner-used"
        wrapper = hostcf / "script" / "repo-jj-archive.ts"
        wrapper.write_text(
            "#!/bin/sh\n"
            f"printf 'host\\n' >> {str(marker)!s}\n"
            f"exec node {str(ROOT / 'archive/repo-jj-archive.ts')!s} \"$@\"\n"
        )
        wrapper.chmod(0o755)
        # The opt-in freshen must discover this exact checkout from the
        # archive root (two parent directories above COMPFUZOR_ARCHIVE).
        freshened = advance(seed, "freshened by self\n")
        # Each case renders from its own playbook dir staged as a slim
        # executing checkout: launcher plus committed bundle, no source.
        def stage(case: str) -> Path:
            play_dir = tmp / case
            (play_dir / "script").mkdir(parents=True, exist_ok=True)
            (play_dir / "archive").mkdir(exist_ok=True)
            shutil.copy2(RUNNER, play_dir / "script/repo-jj-archive.ts")
            shutil.copy2(ROOT / "archive/repo-jj-archive.ts",
                         play_dir / "archive/repo-jj-archive.ts")
            return play_dir

        environment = os.environ | {
            "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"),
            "ANSIBLE_ROLES_PATH": str(ROOT / "roles"),
        }

        def play(case: str, comfuzor_archive: Path, runner: Path | None = None) -> str:
            playbook = stage(case) / "render.pb"
            override = f"\n    COMPFUZOR_REPO_JJ_RUNNER: {str(runner)!r}" if runner else ""
            playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    NAME: fixture
    DIR: {str(tmp / ('deployment-' + case))!r}
    REPO: {str(remote)!r}
    GIT_DIR: {str(tmp / ('deployment-' + case) / 'repo')!r}
    ARCHIVE_SRC: {str(archive)!r}
    COMPFUZOR_ARCHIVE: {str(comfuzor_archive)!r}
    COMPFUZOR_SELF_FRESHEN: true{override}
  tasks:
    - import_role:
        name: compfuzor_repo_notices
    - import_tasks: {str(ROOT / 'tasks/compfuzor/repo_jj_archive.tasks')!r}
""")
            return run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                       cwd=ROOT, env=environment)

        # Host checkout is preferred over the executing playbook's launcher;
        # opt-in freshen fetches its origin without resetting its worktree.
        output = play("a", hostcf)
        assert "host compfuzor checkout" in output, output
        assert output.count("TASK [Compfuzor: announce jj archive runner]") == 1
        assert output.index("TASK [Compfuzor: announce jj archive runner]") < output.index(
            "TASK [Compfuzor: refresh jj deployment workspace]")
        assert marker.read_text() == "host\n", "host launcher should run only for deploy"
        assert run("git", "rev-parse", "refs/remotes/origin/main", cwd=hostcf) == freshened
        assert (archive / ".jj").is_dir()
        # Explicit runner override beats the host checkout.
        marker.unlink(missing_ok=True)
        output = play("b", hostcf, runner=RUNNER)
        assert f"running {RUNNER} (override)" in output, output
        assert not marker.exists(), "override did not bypass the host launcher"
        # Missing host checkout falls back to the playbook_dir launcher.
        marker.unlink(missing_ok=True)
        output = play("c", tmp / "absent")
        assert "(playbook checkout)" in output, output
        assert not marker.exists(), "host launcher used despite missing checkout"
        assert (archive / ".jj").is_dir()
        # A checkout directory with a non-executable launcher is unavailable,
        # not a selected-but-broken runner; use the same playbook fallback.
        wrapper.chmod(0o644)
        marker.unlink(missing_ok=True)
        output = play("d", hostcf)
        assert "(playbook checkout)" in output, output
        assert not marker.exists(), "non-executable host launcher was selected"
