#!/usr/bin/env python3
"""Exercise the archive lane against disposable Git/jj repositories only."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "repo-jj-archive" / "tests"
RUNNER = ROOT / "script" / "repo-jj-archive.py"
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
        "python3", str(RUNNER), "--dest", str(archive), "--repo", str(remote),
        "--remotes", "{}", "--label", "fixture", "--version", version,
        "--update", "true" if update else "false", cwd=archive.parent,
    ))


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
        assert (archive / "local").read_text() == "local commit\n"
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
    GIT_DIR: {str(archive)!r}
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


def test_full_includes_route_primary_to_archive_and_link_it() -> None:
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
    REPO_DIR: {str(archive)!r}
    GIT_DIR: {str(archive)!r}
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
        assert (archive / ".jj").is_dir() and (deployed / "repo").resolve() == archive, output
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


def test_archive_failure_reports_runner_error_not_json_parse_error() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote, _ = create_remote(tmp)
        destination = tmp / "occupied-non-repo"
        destination.mkdir()
        playbook = tmp / "failure.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    DIR: {str(tmp)!r}
    NAME: fixture
    REPO: {str(remote)!r}
    GIT_DIR: {str(destination)!r}
    COMPFUZOR_REPO_JJ_RUNNER: {str(RUNNER)!r}
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor/repo_jj_archive.tasks')!r}
""")
        env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
        output = run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook),
                     cwd=ROOT, env=env, check=False)
        assert "not a colocated Git checkout" in output and "from_json" not in output
