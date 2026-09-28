#!/usr/bin/env python3
"""CLI compatibility contract for the archive toolkit runner.

Companion to tests/integration/repo_jj_archive.test.py (the Ansible-behavior
baseline). This suite pins the *command-line surface* documented in
design/archive-toolkit/compatibility-checks0.glm53.md so the Gunshi -> Effect
CLI migration cannot silently change what the launcher, the Ansible tasks, or
a human invoking `--help` see:

* every failure exits nonzero with **empty stdout** and a single
  `repo-jj-archive: <detail>` line on stderr (help/version/completion are the
  only intentional stdout successes, never JSON);
* argv parsing quirks (equals form, `--` stop-flag, duplicate last-wins,
  legacy flag-only alias, `refresh --version BRANCH` spelling);
* launcher resolution: source-first when its dependencies are installed,
  committed bundle otherwise, and the dependency gate covering every bare
  import of the source entry;
* the committed single-file bundle staying self-contained and directly
  executable.

Baseline tests pass against the current Gunshi implementation. Tests named
`test_intended_*` encode decided post-migration behavior (parent decisions:
real root `--version`, loud `complete` argument rejection) and are marked
xfail until the migration lands them; flip the marker off when they pass.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "archive-cli-contract" / "tests"
SOURCE = ROOT / "archive/src/repo-jj-archive.ts"
BUNDLE = ROOT / "archive/repo-jj-archive.mjs"
RUNNER = ROOT / "script/repo-jj-archive.ts"
SHEBANG = "#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON\n"
NOOP = {"changed": False, "notices": []}

# The launcher must be a transparent transport: every CLI-surface test runs
# against both the TypeScript source entry and the launcher shim.
ENTRIES = (("source", ("node", str(SOURCE))), ("launcher", (str(RUNNER),)))


def run(
    *command: str, cwd: Path, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False, env=env)


def must(*command: str, cwd: Path, env: dict[str, str] | None = None) -> str:
    result = run(*command, cwd=cwd, env=env)
    assert not result.returncode, f"{command} failed:\n{result.stdout}\n{result.stderr}"
    return result.stdout.strip()


def invoke(entry: tuple[str, tuple[str, ...]], *args: str, cwd: Path,
           env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return run(*entry[1], *args, cwd=cwd, env=env)


@contextmanager
def scratch() -> Iterator[Path]:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        yield Path(directory)


def expect_failure(result: subprocess.CompletedProcess[str], *substrings: str) -> None:
    """The umbrella contract: nonzero, stdout empty, one prefixed stderr line."""
    assert result.returncode != 0, (result.returncode, result.stdout, result.stderr)
    assert result.stdout == "", result.stdout
    assert result.stderr.startswith("repo-jj-archive: "), result.stderr
    assert result.stderr.count("\n") <= 1, result.stderr
    for substring in substrings:
        assert substring in result.stderr, result.stderr


def one_json(raw: str) -> dict:
    """Success in --json mode is exactly one JSON line on stdout."""
    assert raw.endswith("\n") and raw.count("\n") == 1, raw
    return json.loads(raw)


def success_json(*command: str, cwd: Path) -> dict:
    result = run(*command, cwd=cwd)
    assert result.returncode == 0, (command, result.stdout, result.stderr)
    assert result.stderr == "", (command, result.stderr)
    return one_json(result.stdout)


def create_remote(tmp: Path) -> tuple[Path, Path]:
    remote = tmp / "upstream.git"
    seed = tmp / "seed"
    must("git", "init", "--bare", str(remote), cwd=tmp)
    must("git", "clone", str(remote), str(seed), cwd=tmp)
    must("git", "config", "user.name", "Archive Test", cwd=seed)
    must("git", "config", "user.email", "archive@example.invalid", cwd=seed)
    (seed / "tracked").write_text("original\n")
    must("git", "add", ".", cwd=seed)
    must("git", "commit", "-m", "initial", cwd=seed)
    must("git", "branch", "-M", "main", cwd=seed)
    must("git", "push", "-u", "origin", "main", cwd=seed)
    must("git", "symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
    return remote, seed


def advance(seed: Path, content: str = "upstream\n") -> str:
    (seed / "tracked").write_text(content)
    must("git", "add", "tracked", cwd=seed)
    must("git", "commit", "-m", "advance", cwd=seed)
    must("git", "push", cwd=seed)
    return must("git", "rev-parse", "HEAD", cwd=seed)


def render(archive: Path, remote: Path, tmp: Path, *, remotes: str = "{}") -> dict:
    return success_json(str(RUNNER), "refresh", "--json", "--dest", str(archive),
                        "--repo", str(remote), "--remotes", remotes,
                        "--label", "fixture", cwd=tmp)


def jj_commit(revision: str, archive: Path) -> str:
    return must("jj", "log", "-G", "-r", revision, "-T", "commit_id", cwd=archive)


# --- Root and per-command help/version surface (matrix rows 10-11, G1) ------


def test_root_help_and_noargs_contract() -> None:
    with scratch() as tmp:
        for entry in ENTRIES:
            result = invoke(entry, "--help", cwd=tmp)
            assert result.returncode == 0, result.stderr
            for needle in ("USAGE:", "refresh", "repo-jj-archive"):
                assert needle in result.stdout, (entry[0], result.stdout)

            result = invoke(entry, cwd=tmp)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == "Run repo-jj-archive --help for commands."

            result = invoke(entry, "-v", cwd=tmp)
            assert result.returncode == 0 and result.stdout.strip() == "0.1.0", result.stderr

            expect_failure(invoke(entry, "-V", cwd=tmp), "Unknown option: -V")

            # Parser precedence quirk: version wins over a preceding --help.
            result = invoke(entry, "--help", "--version", cwd=tmp)
            assert result.returncode == 0 and result.stdout.strip() == "0.1.0"


def test_per_command_version_flag() -> None:
    with scratch() as tmp:
        for entry in ENTRIES:
            for command in ("refresh", "health", "complete"):
                result = invoke(entry, command, "-v", cwd=tmp)
                assert result.returncode == 0 and result.stdout.strip() == "0.1.0", (
                    entry[0], command, result.stdout, result.stderr)


# --- Failure purity: stderr only, never stdout (rows 4/6/7, G2) ------------


def test_parse_failures_are_stderr_only() -> None:
    with scratch() as tmp:
        for entry in ENTRIES:
            expect_failure(invoke(entry, "bogus", cwd=tmp), "Command not found: bogus")
            expect_failure(invoke(entry, "refresh", "--bogus", cwd=tmp),
                           "'--dest' is required", "Unknown option: --bogus")
            expect_failure(invoke(entry, "refresh", "--json", cwd=tmp),
                           "'--dest' is required", "'--repo' is required", "'--label' is required")
            # A dash-leading token is not consumed as --dest's value.
            expect_failure(invoke(entry, "health", "--dest", "--label", "x", cwd=tmp),
                           "'--dest' is required", "Unknown option: --label")


def test_refresh_argument_value_validation() -> None:
    """Value validation fires before any checkout access; no fixture needed."""
    with scratch() as tmp:
        dest = tmp / "never-created"
        base = ("refresh", "--json", "--dest", str(dest), "--repo", str(tmp / "x.git"),
                "--label", "fixture")
        cases = (
            (("--update", "maybe"), "invalid choice: 'maybe'"),
            (("--depth", "0"), "GIT_DEPTH must be positive"),
            (("--depth", "abc"), "GIT_DEPTH must be positive"),
            (("--submodules",), "requires explicit submodule safety handling"),
            (("--remotes", "not-json"), "not valid JSON"),
            (("--remotes", "[]"), "must be a JSON object mapping remote names to URLs"),
        )
        for entry in ENTRIES:
            for extra, message in cases:
                expect_failure(invoke(entry, *base, *extra, cwd=tmp), message)
        assert not dest.exists()


# --- argv parsing quirks (row 9, G3) ----------------------------------------


def test_option_parsing_quirks_are_stable() -> None:
    with scratch() as tmp:
        # A fake archive layout so `self` detection is observable, and an empty
        # HOME so default detection cannot find a real machine checkout.
        checkout = tmp / "archdir" / "rektide" / "compfuzor"
        (checkout / ".git").mkdir(parents=True)
        home = tmp / "empty-home"
        home.mkdir()
        env = dict(os.environ, HOME=str(home))
        detected, undetected = str(checkout), "No compfuzor archive checkout detected"

        for entry in ENTRIES:
            result = invoke(entry, "self", f"--archive-dir={tmp / 'archdir'}", cwd=tmp, env=env)
            assert result.returncode == 0 and detected in result.stdout, result.stderr

            # `--` stops flag parsing: the override must NOT be applied.
            result = invoke(entry, "self", "--", f"--archive-dir={tmp / 'archdir'}", cwd=tmp, env=env)
            assert result.returncode == 0 and result.stdout.strip() == undetected

            # Duplicate flags: last one wins.
            result = invoke(entry, "self", "--archive-dir", str(tmp / "absent"),
                            "--archive-dir", str(tmp / "archdir"), cwd=tmp, env=env)
            assert result.returncode == 0 and detected in result.stdout

            # Stray token after a boolean flag and unknown positional are tolerated.
            result = invoke(entry, "self", "--freshen", "true", cwd=tmp, env=env)
            assert result.returncode == 0 and result.stdout.strip() == undetected
            result = invoke(entry, "self", "extra", cwd=tmp, env=env)
            assert result.returncode == 0 and result.stdout.strip() == undetected


# --- Completion for supported shells (row 12, G4) ---------------------------

SUPPORTED_SHELLS = ("bash", "zsh", "fish", "powershell")


def test_completion_scripts_for_supported_shells() -> None:
    with scratch() as tmp:
        for entry in ENTRIES:
            scripts: dict[str, str] = {}
            for shell in SUPPORTED_SHELLS:
                result = invoke(entry, "complete", shell, cwd=tmp)
                assert result.returncode == 0, (entry[0], shell, result.stderr)
                assert result.stderr == "", (entry[0], shell, result.stderr)
                assert result.stdout, (entry[0], shell)
                assert ("repo-jj-archive" in result.stdout
                        or "repo_jj_archive" in result.stdout), (entry[0], shell)
                scripts[shell] = result.stdout
            # Generated bash must at least parse.
            script = tmp / "completion.bash"
            script.write_text(scripts["bash"])
            must("bash", "-n", str(script), cwd=tmp)
            result = invoke(entry, "complete", "--help", cwd=tmp)
            assert result.returncode == 0 and "complete" in result.stdout


# --- Refresh parity across source, launcher, and standalone bundle ----------


def test_refresh_json_contract_parity_across_entry_paths() -> None:
    with scratch() as tmp:
        remote, _ = create_remote(tmp)
        archive = tmp / "archive"
        assert render(archive, remote, tmp)["changed"] and (archive / ".jj").is_dir()

        refresh = ("--dest", str(archive), "--repo", str(remote),
                   "--remotes", "{}", "--label", "fixture")
        # Source entry and launcher produce the same one-JSON-line NOOP.
        assert success_json("node", str(SOURCE), "refresh", "--json", *refresh,
                            cwd=tmp) == NOOP
        assert success_json(str(RUNNER), "refresh", "--json", *refresh, cwd=tmp) == NOOP

        # The committed bundle, copied alone (no launcher, no source, no deps).
        standalone = tmp / "standalone"
        standalone.mkdir()
        shutil.copy2(BUNDLE, standalone / "repo-jj-archive.mjs")
        assert success_json(str(standalone / "repo-jj-archive.mjs"), "refresh", "--json",
                            *refresh, cwd=standalone) == NOOP

        # Legacy flag-only alias is refresh --json; --version spells --branch.
        legacy = ("--dest", str(archive), "--repo", str(remote),
                  "--remotes", "{}", "--label", "fixture")
        assert success_json(str(RUNNER), *legacy, cwd=tmp) == NOOP
        assert success_json(str(RUNNER), *legacy, "--version", "main", cwd=tmp) == NOOP


def test_refresh_branch_at_remote_selects_declared_remote() -> None:
    with scratch() as tmp:
        remote, seed = create_remote(tmp)
        # Leave the peer one commit behind so selection is observable.
        peer = tmp / "peer.git"
        must("git", "clone", "--bare", str(remote), str(peer), cwd=tmp)
        peer_tip = must("git", "-C", str(peer), "rev-parse", "main", cwd=tmp)
        origin_tip = advance(seed)
        assert peer_tip != origin_tip

        archive = tmp / "archive"
        remotes = json.dumps({"peer": str(peer)})
        assert render(archive, remote, tmp, remotes=remotes)["changed"]
        assert jj_commit("main", archive) == origin_tip

        selected = success_json(str(RUNNER), "refresh", "--json", "--dest", str(archive),
                                "--repo", str(remote), "--remotes", remotes, "--label", "fixture",
                                "--branch", "main@peer", cwd=tmp)
        assert selected["changed"]
        assert any(f"(peer)" in n.get("message", "") for n in selected["notices"])
        preserved = next(n for n in selected["notices"]
                         if n["kind"] == "bookmark-created" and "/main-" in n["name"])
        assert preserved["target"] == origin_tip
        assert jj_commit("main", archive) == peer_tip

        # Legacy `refresh --version BRANCH` spelling equals `--branch BRANCH`.
        reverted = success_json(str(RUNNER), "refresh", "--json", "--dest", str(archive),
                                "--repo", str(remote), "--remotes", remotes, "--label", "fixture",
                                "--version", "main", cwd=tmp)
        assert reverted["changed"] and jj_commit("main", archive) == origin_tip


# --- Launcher resolution order (rows 1-2, G5/G6) ----------------------------


def test_launcher_prefers_source_when_dependencies_present() -> None:
    with scratch() as tmp:
        remote, _ = create_remote(tmp)
        tree = tmp / "tree"
        (tree / "script").mkdir(parents=True)
        shutil.copy2(RUNNER, tree / "script/repo-jj-archive.ts")
        shutil.copytree(ROOT / "archive/src", tree / "archive/src")
        # A poisoned bundle proves the healthy source (with deps) wins.
        (tree / "archive/repo-jj-archive.mjs").write_text(
            'throw Error("bundle must not run while source deps are installed")\n')
        os.symlink(ROOT / "node_modules", tree / "node_modules")

        checkout = tmp / "checkout"
        result = run(str(tree / "script/repo-jj-archive.ts"), "refresh", "--json",
                     "--dest", str(checkout), "--repo", str(remote), "--label", "fixture",
                     cwd=tree)
        assert result.returncode == 0 and result.stderr == "", result.stderr
        assert one_json(result.stdout)["changed"] and (checkout / ".jj").is_dir()


def test_launcher_falls_back_to_bundle_when_dependencies_absent() -> None:
    with scratch() as tmp:
        tree = tmp / "tree"
        (tree / "script").mkdir(parents=True)
        shutil.copy2(RUNNER, tree / "script/repo-jj-archive.ts")
        shutil.copytree(ROOT / "archive/src", tree / "archive/src")
        # Healthy source but no node_modules: the poisoned bundle must be chosen.
        (tree / "archive/repo-jj-archive.mjs").write_text(
            'throw Error("bundle fallback marker")\n')
        expect_failure(run(str(tree / "script/repo-jj-archive.ts"), "refresh", "--json",
                           "--dest", str(tmp / "out"), "--repo", str(tmp / "x.git"),
                           "--label", "fixture", cwd=tree),
                       "bundle fallback marker")


def test_launcher_reports_missing_runner_module() -> None:
    with scratch() as tmp:
        tree = tmp / "tree"
        (tree / "script").mkdir(parents=True)
        shutil.copy2(RUNNER, tree / "script/repo-jj-archive.ts")
        shutil.copytree(ROOT / "archive/src", tree / "archive/src")
        # No node_modules and no bundle: resolution itself fails loudly.
        expect_failure(run(str(tree / "script/repo-jj-archive.ts"), "refresh", "--json",
                           "--dest", str(tmp / "out"), "--repo", str(tmp / "x.git"),
                           "--label", "fixture", cwd=tree),
                       "Cannot find module")


def test_standalone_bundle_executes_without_launcher_or_dependencies() -> None:
    with scratch() as tmp:
        remote, _ = create_remote(tmp)
        solo = tmp / "solo"
        solo.mkdir()
        shutil.copy2(BUNDLE, solo / "repo-jj-archive.mjs")

        for label, command in (("shebang", (str(solo / "repo-jj-archive.mjs"),)),
                               ("node", ("node", str(solo / "repo-jj-archive.mjs")))):
            checkout = tmp / f"checkout-{label}"
            result = run(*command, "refresh", "--json", "--dest", str(checkout),
                         "--repo", str(remote), "--label", "fixture", cwd=solo)
            assert result.returncode == 0 and result.stderr == "", (label, result.stderr)
            assert one_json(result.stdout)["changed"] and (checkout / ".jj").is_dir()


# --- Static contracts: bundle shape and the launcher dependency gate ---------

# Line-anchored so prose like "choose from 'true', 'false'" in error messages
# and JSDoc mentions of `from 'gunshi/context'` never count as imports.
IMPORT_STATEMENT = re.compile(
    r"""^\s*import\s+[^;\n]*?\bfrom\s+["']([^"']+)["']""", re.MULTILINE)
EXPORT_FROM = re.compile(
    r"""^\s*export\s+[^;\n]*?\bfrom\s+["']([^"']+)["']""", re.MULTILINE)
SIDE_EFFECT_IMPORT = re.compile(
    r"""^\s*import\s+["']([^"']+)["']""", re.MULTILINE)
DYNAMIC_IMPORT = re.compile(r"""\bimport\s*\(\s*["']""")


def import_closure(entry: Path) -> list[Path]:
    """Every module the entry transitively loads via relative imports."""
    seen: dict[Path, None] = {}
    pending = [entry]
    while pending:
        current = pending.pop()
        if current in seen or not current.is_file():
            continue
        seen[current] = None
        text = current.read_text()
        specifiers = IMPORT_STATEMENT.findall(text) + EXPORT_FROM.findall(text) \
            + SIDE_EFFECT_IMPORT.findall(text)
        pending.extend(
            current.parent / specifier for specifier in specifiers
            if specifier.startswith(".")
        )
    return list(seen)


def bare_packages(paths: list[Path]) -> set[str]:
    """Package names of every non-relative, non-node: import in the sources."""
    specifiers: set[str] = set()
    for path in paths:
        text = path.read_text()
        specifiers |= set(IMPORT_STATEMENT.findall(text))
        specifiers |= set(EXPORT_FROM.findall(text))
        specifiers |= set(SIDE_EFFECT_IMPORT.findall(text))
    external = {s for s in specifiers if not s.startswith((".", "node:"))}
    return {
        "/".join(specifier.split("/")[:2]) if specifier.startswith("@")
        else specifier.split("/")[0]
        for specifier in external
    }


def test_bundle_is_self_contained() -> None:
    text = BUNDLE.read_text()
    assert text.startswith(SHEBANG)
    assert "export { main }" in text
    assert "0.1.0" in text
    assert not DYNAMIC_IMPORT.search(text), "dynamic imports break single-file use"
    for specifier in IMPORT_STATEMENT.findall(text):
        assert specifier.startswith("node:"), specifier
    for path in (RUNNER, SOURCE, BUNDLE):
        assert path.read_text().startswith(SHEBANG), path
        assert os.access(path, os.X_OK), path


def test_launcher_dependency_gate_covers_every_bare_import() -> None:
    """The stat() gate must list every bare package the entry can load.

    Scans the transitive import closure of the CLI entry — not merely files
    present in the tree — so in-flight modules not yet wired in do not trip
    the guard, while any dependency the entry actually gains must be added to
    the launcher's sourceFiles list in lockstep. A stale list silently degrades
    the launcher to bundle-always and the source path becomes dead code; this
    is the guard.
    """
    launcher = RUNNER.read_text()
    gated = set(re.findall(r"node_modules/[^\"']+", launcher))
    reachable = import_closure(SOURCE)
    assert SOURCE in reachable and len(reachable) > 1
    missing = {f"node_modules/{name}" for name in bare_packages(reachable)} - gated
    assert not missing, f"bare imports not covered by launcher gate: {sorted(missing)}"


# --- Decided post-migration behavior (fails on the Gunshi baseline) ---------


@pytest.mark.xfail(
    reason="intended post-migration surface: root --version must print the "
           "toolkit version instead of the legacy refresh --branch hijack",
    strict=False,
)
def test_intended_root_version_prints_toolkit_version() -> None:
    result = run("node", str(SOURCE), "--version", cwd=ROOT)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "0.1.0" and result.stderr == ""


@pytest.mark.xfail(
    reason="intended post-migration surface: complete with an unsupported "
           "shell must fail on stderr rather than Gunshi's silent rc0",
    strict=False,
)
def test_intended_complete_unknown_shell_is_rejected() -> None:
    expect_failure(run("node", str(SOURCE), "complete", "bogus", cwd=ROOT))


@pytest.mark.xfail(
    reason="intended post-migration surface: complete without a shell argument "
           "must fail on stderr rather than emitting the ':4' directive oddity",
    strict=False,
)
def test_intended_complete_requires_a_shell_argument() -> None:
    expect_failure(run("node", str(SOURCE), "complete", cwd=ROOT))
