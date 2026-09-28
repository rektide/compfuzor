#!/usr/bin/env python3
"""CLI compatibility contract for the archive toolkit runner.

Companion to tests/integration/repo_jj_archive.test.py (the Ansible-behavior
baseline). This suite pins the *command-line surface* of the Effect CLI
implementation against the compatibility commitments in
design/archive-toolkit/direction0.gpt6astra.md (recorded after the migration
review): documented argv and machine output are preserved, while incidental
Gunshi parsing is not:

* every failure exits nonzero with **empty stdout** and a single
  `repo-jj-archive: <detail>` line on stderr (help/version/completion are the
  only intentional stdout successes, never JSON) — the exact wording of
  Effect's native parse errors is not pinned, only that the offending token is
  named on stderr;
* native semantics that differ from Gunshi are asserted as the contract:
  help heading without a colon, one-missing-flag-at-a-time reporting,
  duplicate **first-wins** flags, strict rejection of unexpected positionals
  (including after `--`), and root help-over-version action precedence;
* root `--version` prints the toolkit version and the native `--completions`
  action works — neither is stolen by the legacy flag-only refresh adapter,
  while the legacy adapter itself (flag-only `refresh --json`, the
  `--version BRANCH` -> `--branch BRANCH` spelling, `--` stopping the scan)
  keeps working;
* launcher resolution: source-first when its dependencies are installed,
  committed bundle otherwise, and the dependency gate covering every bare
  import of the source entry;
* the committed single-file bundle staying self-contained and directly
  executable.

The `complete` command and the native `--completions` action both serve
bash/zsh/fish from Effect's command-tree generator; PowerShell comes from the
static generator (subcommand names and global flags only — a documented
coverage reduction, see archive/README.md).
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


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "archive-cli-contract" / "tests"
SOURCE = ROOT / "archive/src/repo-jj-archive.ts"
BUNDLE = ROOT / "archive/repo-jj-archive.ts"
RUNNER = ROOT / "script/repo-jj-archive.ts"
SHEBANG = "#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON\n"
NOOP = {"changed": False, "notices": []}

# Gunshi printed "USAGE:"; Effect prints a bare "USAGE" heading. The contract
# is a usage section naming the binary, not the colon.
USAGE_HEADING = re.compile(r"^USAGE:?\s*$", re.MULTILINE)

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


# --- Root and per-command help/version surface -------------------------------


def test_root_help_and_noargs_contract() -> None:
    with scratch() as tmp:
        for entry in ENTRIES:
            result = invoke(entry, "--help", cwd=tmp)
            assert result.returncode == 0, result.stderr
            assert USAGE_HEADING.search(result.stdout), (entry[0], result.stdout)
            for needle in ("refresh", "repo-jj-archive"):
                assert needle in result.stdout, (entry[0], needle, result.stdout)

            result = invoke(entry, cwd=tmp)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == "Run repo-jj-archive --help for commands."

            # Root version is real: both spellings print the toolkit version.
            for flag in ("-v", "--version"):
                result = invoke(entry, flag, cwd=tmp)
                assert result.returncode == 0, (entry[0], flag, result.stderr)
                assert result.stdout.strip() == "0.1.0" and result.stderr == ""

            # The short-flag set is exactly -h/-v; -V is an unknown flag.
            expect_failure(invoke(entry, "-V", cwd=tmp), "-V")

            # Root action precedence follows the native parser: help wins over
            # version regardless of argv order (Gunshi let version win).
            for order in (("--help", "--version"), ("--version", "--help")):
                result = invoke(entry, *order, cwd=tmp)
                assert result.returncode == 0, (entry[0], order, result.stderr)
                assert USAGE_HEADING.search(result.stdout), (entry[0], order, result.stdout)


def test_per_command_version_flag() -> None:
    with scratch() as tmp:
        for entry in ENTRIES:
            for command in ("refresh", "health", "complete"):
                result = invoke(entry, command, "-v", cwd=tmp)
                assert result.returncode == 0 and result.stdout.strip() == "0.1.0", (
                    entry[0], command, result.stdout, result.stderr)


# --- Failure purity: stderr only, never stdout --------------------------------


def test_parse_failures_are_stderr_only() -> None:
    """Native wording, contract shape: the offending token is named on stderr.

    Effect reports one missing flag at a time rather than Gunshi's aggregate;
    the contract is that a missing required flag is reported (here --dest,
    the first one), with stdout still empty.
    """
    with scratch() as tmp:
        for entry in ENTRIES:
            expect_failure(invoke(entry, "bogus", cwd=tmp), "bogus")
            expect_failure(invoke(entry, "refresh", "--bogus", cwd=tmp), "--bogus")
            expect_failure(invoke(entry, "refresh", "--json", cwd=tmp),
                           "--dest", "required")
            # A dash-leading token is not consumed as --dest's value.
            expect_failure(invoke(entry, "health", "--dest", "--label", "x", cwd=tmp),
                           "--dest", "--label")


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


# --- argv parsing semantics ----------------------------------------------------


def test_option_parsing_contract() -> None:
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

            # Duplicate flags: the first occurrence wins (authorized Effect
            # change; Gunshi applied the last).
            result = invoke(entry, "self", "--archive-dir", str(tmp / "absent"),
                            "--archive-dir", str(tmp / "archdir"), cwd=tmp, env=env)
            assert result.returncode == 0 and result.stdout.strip() == undetected

            # A stray token after a boolean flag stays tolerated...
            result = invoke(entry, "self", "--freshen", "true", cwd=tmp, env=env)
            assert result.returncode == 0 and result.stdout.strip() == undetected

            # ...but unexpected positionals are rejected (authorized Effect
            # change; Gunshi silently ignored them).
            expect_failure(invoke(entry, "self", "extra", cwd=tmp, env=env), "extra")

            # `--` ends flag parsing: a bare separator is fine, and a flag
            # after it is a positional — rejected, never applied.
            result = invoke(entry, "self", "--", cwd=tmp, env=env)
            assert result.returncode == 0 and result.stdout.strip() == undetected
            expect_failure(invoke(entry, "self", "--", f"--archive-dir={tmp / 'archdir'}",
                                  cwd=tmp, env=env), "--archive-dir")

            # A leading `--` also hides refresh flags from the legacy adapter:
            # this is a positional-only root invocation, not flag-only refresh.
            expect_failure(invoke(entry, "--", "--dest", str(tmp), cwd=tmp), "--dest")


# --- Completion for supported shells ------------------------------------------

SUPPORTED_SHELLS = ("bash", "zsh", "fish", "powershell")
# Effect's native generator; PowerShell is served only by `complete` via the
# static generator, so it is not part of the native-action assertions.
NATIVE_SHELLS = ("bash", "zsh", "fish")


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

            # The native `--completions` action is not stolen by the legacy
            # refresh adapter and prints the same script as `complete`.
            for shell in NATIVE_SHELLS:
                native = invoke(entry, "--completions", shell, cwd=tmp)
                assert native.returncode == 0, (entry[0], shell, native.stderr)
                assert native.stderr == "", (entry[0], shell, native.stderr)
                assert native.stdout == scripts[shell], (entry[0], shell)

            # Unsupported shells and a missing shell argument are loud
            # failures (the intended surface; Gunshi silently no-opped).
            expect_failure(invoke(entry, "complete", "bogus", cwd=tmp), "bogus")
            expect_failure(invoke(entry, "complete", cwd=tmp))


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
        # Node 26 type-strips the erased-JS .ts artifact natively.
        standalone = tmp / "standalone"
        standalone.mkdir()
        shutil.copy2(BUNDLE, standalone / "repo-jj-archive.ts")
        assert success_json(str(standalone / "repo-jj-archive.ts"), "refresh", "--json",
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
        assert any("advanced checkout to main@peer" in n.get("message", "") for n in selected["notices"])
        assert jj_commit("main", archive) == origin_tip  # Shared local bookmark stays ahead.
        assert jj_commit("@-", archive) == peer_tip

        # Legacy `refresh --version BRANCH` spelling equals `--branch BRANCH`.
        reverted = success_json(str(RUNNER), "refresh", "--json", "--dest", str(archive),
                                "--repo", str(remote), "--remotes", remotes, "--label", "fixture",
                                "--version", "main", cwd=tmp)
        assert reverted["changed"] and jj_commit("main", archive) == origin_tip

        # The same spelling inside a flag-only legacy invocation (no
        # subcommand, dest flags present) still selects the declared remote.
        flagged = success_json(str(RUNNER), "--dest", str(archive), "--repo", str(remote),
                               "--remotes", remotes, "--label", "fixture",
                               "--version", "main@peer", cwd=tmp)
        assert flagged["changed"]
        assert any("advanced checkout to main@peer" in n.get("message", "") for n in flagged["notices"])
        assert jj_commit("main", archive) == origin_tip
        assert jj_commit("@-", archive) == peer_tip


# --- Launcher resolution order ------------------------------------------------


def test_launcher_prefers_source_when_dependencies_present() -> None:
    with scratch() as tmp:
        remote, _ = create_remote(tmp)
        tree = tmp / "tree"
        (tree / "script").mkdir(parents=True)
        shutil.copy2(RUNNER, tree / "script/repo-jj-archive.ts")
        shutil.copytree(ROOT / "archive/src", tree / "archive/src")
        # A poisoned bundle proves the healthy source (with deps) wins.
        (tree / "archive/repo-jj-archive.ts").write_text(
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
        (tree / "archive/repo-jj-archive.ts").write_text(
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
        shutil.copy2(BUNDLE, solo / "repo-jj-archive.ts")

        for label, command in (("shebang", (str(solo / "repo-jj-archive.ts"),)),
                               ("node", ("node", str(solo / "repo-jj-archive.ts")))):
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
    assert "export { main, runExecutable }" in text
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
