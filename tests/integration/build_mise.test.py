#!/usr/bin/env python3
"""Build-time pin/link lifecycle in disposable deployments and jj checkouts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "build-mise"


def run(*command: str, cwd: Path, env: dict[str, str] | None = None, check: bool = True) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, check=False)
    if check and result.returncode:
        raise AssertionError(f"{command} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def render(tmp: Path, *, version_vars: str, initial_bins: str = "[]", link_bypass: bool = False) -> tuple[Path, dict]:
    deployment = tmp / "deployment"
    repository = tmp / "repo"
    deployment.mkdir(exist_ok=True)
    (deployment / "bin").mkdir(exist_ok=True)
    repository.mkdir(exist_ok=True)
    (tmp / "files").symlink_to(ROOT / "files", target_is_directory=True)
    (tmp / "vars").symlink_to(ROOT / "vars", target_is_directory=True)
    playbook = tmp / "render.pb"
    output = tmp / "result.json"
    playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: opt
    NAME: fixture
    DIR: {str(deployment)!r}
    BINS_DIR: {str(deployment / 'bin')!r}
    REPO_DIR: {str(repository)!r}
    BINMODE: '0755'
    DEFAULT_HELPERS: [env, setopts, loud]
    BINS: {initial_bins}
    ETC_FILES: []
    LINKS: []
    TOOL_VERSIONS_LINK_BYPASS: {str(link_bypass).lower()}
    {version_vars}
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor/gen_tool_versions.tasks')!r}
    - ansible.builtin.template:
        src: {str(ROOT / 'files/_bin')!r}
        dest: {str(deployment / 'bin/build-mise.sh')!r}
        mode: '0755'
      vars:
        item: "{{{{ BINS | selectattr('name', 'equalto', 'build-mise.sh') | first }}}}"
    - ansible.builtin.copy:
        dest: {str(output)!r}
        content: "{{{{ {{'bins': BINS, 'etc': ETC_FILES, 'links': LINKS, 'composers': BINS | bin_composers}} | to_json }}}}"
""")
    env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
    run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), cwd=ROOT, env=env)
    return deployment / "bin/build-mise.sh", json.loads(output.read_text())


def mise_env(tmp: Path, deploy: Path) -> dict[str, str]:
    stub = tmp / "stub"
    stub.mkdir(exist_ok=True)
    (stub / "mise").write_text('#!/bin/sh\nprintf "mise:%s\\n" "$PWD" >> "$MISE_TEST_LOG"\n')
    (stub / "mise").chmod(0o755)
    # The minimal PATH below only needs to shadow `mise` with the stub. Keep
    # the test process's own node resolvable ahead of /usr/bin as well: the
    # repo-jj-archive runner is TypeScript executed directly by node, and
    # distro node builds may lack compile-time TypeScript support.
    node = Path(shutil.which("node") or "/usr/bin/node").resolve().parent
    return os.environ | {"DIR": str(deploy), "MISE_TEST_LOG": str(tmp / "mise.log"),
                         "PATH": f"{stub}:{node}:/usr/local/bin:/usr/bin:/bin"}


def test_build_mise_orders_before_consumers_and_excludes_new_link() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        script, data = render(tmp, version_vars='TOOL_VERSIONS: {nodejs: "26"}',
                              initial_bins='[{name: build-nodejs.sh, generated: "echo later", run: true}]')
        assert data["etc"] == [] and data["links"] == []
        assert data["bins"][0]["name"] == "build-mise.sh"
        build = next(bin for bin in data["composers"] if bin["name"] == "build.sh")
        assert build["run_all"] == ["build-mise.sh", "build-nodejs.sh"]
        repo = tmp / "repo"
        run("jj", "git", "init", "--colocate", cwd=repo)
        deploy = tmp / "deployment"
        env = mise_env(tmp, deploy)
        assert run(str(script), cwd=tmp, env=env) == ""
        assert (deploy / ".tool-versions").read_text() == "nodejs 26\n"
        assert (repo / ".tool-versions").is_symlink()
        assert (repo / ".tool-versions").resolve() == (deploy / ".tool-versions")
        assert (repo / ".git/info/exclude").read_text().splitlines().count("/.tool-versions") == 1
        assert "The working copy has no changes" in run("jj", "status", cwd=repo)
        run(str(script), cwd=tmp, env=env)
        assert (repo / ".git/info/exclude").read_text().splitlines().count("/.tool-versions") == 1
        assert (tmp / "mise.log").read_text().splitlines() == [f"mise:{deploy}"] * 2


def test_build_mise_preserves_repo_file_reports_diff_and_force_is_explicit() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        script, data = render(tmp, version_vars='MISE_VERSIONS: {nodejs: "26"}')
        assert data["etc"] == [] and data["links"] == []
        repo = tmp / "repo"
        run("jj", "git", "init", "--colocate", cwd=repo)
        (repo / "mise.toml").write_text('[tools]\nnodejs = "old"\n')
        env = mise_env(tmp, tmp / "deployment")
        stdout = run(str(script), cwd=tmp, env=env)
        assert "COMPFUZOR_REPO_VERSION_SKIP\t" in stdout
        assert "-nodejs = \"old\"" in stdout and "+nodejs = \"26\"" in stdout
        assert (repo / "mise.toml").read_text() == '[tools]\nnodejs = "old"\n'
        assert "mise:" in (tmp / "mise.log").read_text()
        skip = run(str(script), cwd=tmp, env=env | {"COMPFUZOR_MISE_BYPASS": "1"})
        assert "skipped" not in skip and (tmp / "mise.log").read_text().count("mise:") == 1
        forced = run(str(script), cwd=tmp, env=env | {"COMPFUZOR_MISE_LINK_FORCE": "1"})
        assert "FORCED VERSION LINK" in forced
        assert (repo / "mise.toml").is_symlink()
        assert (repo / "mise.toml").resolve() == tmp / "deployment/mise.toml"


def test_build_mise_links_pin_into_jj_workspace_deployment() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        script, data = render(tmp, version_vars='TOOL_VERSIONS: {rust: "1"}')
        assert data["etc"] == [] and data["links"] == []
        # The repo_jj_archive lane deploys a jj workspace created with
        # `jj workspace add --colocate`: its .git is a gitdir *file*, not a
        # directory, so the exclude must resolve through git's common dir.
        remote = tmp / "upstream.git"
        run("git", "init", "--bare", str(remote), cwd=tmp)
        archive = tmp / "archive"
        run("jj", "git", "clone", "--colocate", str(remote), str(archive), cwd=tmp)
        run("jj", "workspace", "add", "--colocate", "--revision", "main@", str(tmp / "repo"),
            cwd=archive, check=False)
        (tmp / "repo" / ".git").exists() or run(
            "jj", "workspace", "add", "--colocate", str(tmp / "repo"), cwd=archive)
        assert (tmp / "repo" / ".git").is_file()
        deploy = tmp / "deployment"
        env = mise_env(tmp, deploy) | {"REPO_DIR": str(tmp / "repo")}
        assert run(str(script), cwd=tmp, env=env) == ""
        assert (deploy / ".tool-versions").read_text() == "rust 1\n"
        assert (tmp / "repo" / ".tool-versions").is_symlink()
        assert (tmp / "repo" / ".tool-versions").resolve() == deploy / ".tool-versions"
        assert (archive / ".git/info/exclude").read_text().splitlines().count("/.tool-versions") == 1
        assert "The working copy has no changes" in run("jj", "status", cwd=tmp / "repo")
        assert "The working copy has no changes" in run("jj", "status", cwd=archive)


def test_full_render_collects_mise_diff_after_build_run() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        remote = tmp / "upstream.git"
        seed = tmp / "seed"
        archive = tmp / "archive"
        deploy = tmp / "fixture"
        deploy.mkdir()
        run("git", "init", "--bare", str(remote), cwd=tmp)
        run("git", "clone", str(remote), str(seed), cwd=tmp)
        run("git", "config", "user.name", "Mise Test", cwd=seed)
        run("git", "config", "user.email", "mise@example.invalid", cwd=seed)
        (seed / "mise.toml").write_text('[tools]\nnodejs = "old"\n')
        run("git", "add", "mise.toml", cwd=seed)
        run("git", "commit", "-m", "pin", cwd=seed)
        run("git", "branch", "-M", "main", cwd=seed)
        run("git", "push", "-u", "origin", "main", cwd=seed)
        run("git", "symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
        run("jj", "git", "clone", "--colocate", str(remote), str(archive), cwd=tmp)
        (tmp / "files").symlink_to(ROOT / "files", target_is_directory=True)
        (tmp / "vars").symlink_to(ROOT / "vars", target_is_directory=True)
        playbook = tmp / "build-render.pb"
        playbook.write_text(f"""---
- hosts: all
  gather_facts: false
  vars:
    TYPE: opt
    type: opt
    NAME: fixture
    INSTANCE: main
    DIR: {str(deploy)!r}
    ETC: {str(deploy / 'etc')!r}
    HOMEDIR: {str(tmp / 'home')!r}
    ARCHIVE_SRC: {str(archive)!r}
    REPO_DIR: {str(archive)!r}
    GIT_DIR: {str(archive)!r}
    REPO: {str(remote)!r}
    ARCHIVE_DOWNLOAD: true
    GIT_UPDATE: false
    COMPFUZOR_REPO_JJ_RUNNER: {str(ROOT / 'script/repo-jj-archive.ts')!r}
    MISE_VERSIONS: {{nodejs: '26'}}
    PKGS_BYPASS: true
    APT_BYPASS: true
    FS_BYPASS: true
    DIR_BYPASS: true
    ENV_BYPASS: true
    LINKS_BYPASS: true
    GLOBAL_BINS_BYPASS: true
    SYSTEMD_THUNK_BYPASS: true
  tasks:
    - import_tasks: {str(ROOT / 'tasks/compfuzor.includes')!r}
""")
        env = mise_env(tmp, deploy) | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"),
                                      "ANSIBLE_ROLES_PATH": str(ROOT / "roles")}
        output = run("ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), cwd=ROOT, env=env)
        assert "REPO VERSION CONFIG EXISTS" in output and "REPO NOTICE  -nodejs =" in output, output[-5000:]
        assert "REPO NOTICE  +nodejs =" in output
        assert (archive / "mise.toml").read_text() == '[tools]\nnodejs = "old"\n'
        assert (archive / ".git/info/exclude").read_text().splitlines().count("/mise.toml") == 1
        assert (deploy / "mise.toml").read_text() == '[tools]\nnodejs = "26"\n'
