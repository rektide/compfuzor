"""Real source-entry Effect CLI custody contract (bundle rebuilt separately)."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "archive/src/repo-jj-archive.ts"
LAUNCHER = ROOT / "script/repo-jj-archive.ts"
SCRATCH = ROOT / ".test-agent/archive-custody-cli/tests"


def run(cwd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")
    return subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, check=False)


def must(cwd: Path, *args: str) -> str:
    outcome = run(cwd, *args)
    assert outcome.returncode == 0, (args, outcome.stdout, outcome.stderr)
    return outcome.stdout.strip()


def invoke(cwd: Path, *args: str, launcher: bool = False) -> subprocess.CompletedProcess[str]:
    entry = (str(LAUNCHER),) if launcher else ("node", str(SOURCE))
    return run(cwd, *entry, *args)


def success_json(result: subprocess.CompletedProcess[str]) -> dict:
    assert result.returncode == 0 and result.stderr == "", (result.stdout, result.stderr)
    assert result.stdout.endswith("\n") and result.stdout.count("\n") == 1, result.stdout
    return json.loads(result.stdout)


def failure(result: subprocess.CompletedProcess[str]) -> None:
    assert result.returncode != 0 and result.stdout == "", (result.stdout, result.stderr)
    assert result.stderr.startswith("repo-jj-archive: "), result.stderr


def fixture(tmp: Path, *, sensitive: bool = False) -> tuple[Path, Path, tuple[str, ...]]:
    source, dest = tmp / "legacy", tmp / "archive"
    source.mkdir()
    must(source, "git", "init", "-q", "-b", "main")
    must(source, "git", "config", "user.name", "custody fixture")
    must(source, "git", "config", "user.email", "fixture@example.invalid")
    (source / "tracked.txt").write_text("historical\n")
    if sensitive:
        (source / ".env").write_text("PRIVATE=never print this content\n")
    must(source, "git", "add", "-f", ".")
    must(source, "git", "commit", "-qm", "initial")
    must(tmp, "git", "clone", "-q", "--no-hardlinks", str(source), str(dest))
    must(dest, "jj", "git", "init", "--colocate")
    args = ("--legacy", str(source), "--dest", str(dest), "--repo", str(source),
            "--label", "legacy")
    return source, dest, args


def test_cli_plan_apply_retry_and_verify_after_source_removed() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        source, dest, args = fixture(tmp)
        before = must(source, "git", "rev-parse", "HEAD")
        planned = success_json(invoke(tmp, "adopt", *args, "--json"))
        assert planned["state"] == "ready" and planned["headManifestSha256"]
        assert planned["source"]["head"]["treePaths"]
        assert planned["baselines"]["selectedBranch"] == "main"
        assert not list(tmp.glob(".compfuzor-adoptions/**/source.bundle"))
        first = success_json(invoke(tmp, "adopt", *args, "--apply", "--json"))
        assert first["changed"] and first["verification"]["custodyVerified"]
        assert first["receiptRef"] == "refs/adopt/receipts/legacy/g0"
        assert must(source, "git", "rev-parse", "HEAD") == before
        assert (dest / "tracked.txt").read_text() == "historical\n"
        repeated = success_json(invoke(tmp, "adopt", *args, "--apply", "--json"))
        assert not repeated["changed"] and repeated["receiptCommitOid"] == first["receiptCommitOid"]
        source.rename(tmp / "legacy-retired-fixture")
        verified = success_json(invoke(tmp, "verify-adoption", "--dest", str(dest),
                                       "--receipt", first["receiptRef"], "--json"))
        assert verified["custodyVerified"] and verified["receiptCommitOid"] == first["receiptCommitOid"]
        assert verified["sourceDrift"] == "unknown"
        absent = success_json(invoke(tmp, "verify-adoption", "--dest", str(dest),
                                     "--receipt", first["receiptRef"], "--legacy", str(source),
                                     "--json", launcher=True))
        assert absent["custodyVerified"] and absent["sourceDrift"] == "absent"
        failure(invoke(tmp, "verify-adoption", "--dest", str(dest),
                       "--receipt", "refs/adopt/receipts/legacy/missing", "--json"))
        # An installed receipt cannot count as verified once a required pin is missing.
        branch_pin = must(dest, "git", "for-each-ref", "--format=%(refname)",
                          "refs/heads/harvest/legacy/g0/branch").splitlines()[0]
        must(dest, "git", "update-ref", "-d", branch_pin)
        failure(invoke(tmp, "verify-adoption", "--dest", str(dest),
                       "--receipt", first["receiptRef"], "--json"))


def test_blocked_plan_missing_destination_and_stale_review_fail_closed() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        source, dest, args = fixture(tmp, sensitive=True)
        blocked = success_json(invoke(tmp, "adopt", *args, "--json"))
        assert blocked["state"] == "blocked"
        assert any(issue["code"] == "clean-head-path-review-required" for issue in blocked["blockers"])
        assert "PRIVATE=never" not in json.dumps(blocked)
        failure(invoke(tmp, "adopt", *args, "--apply", "--json"))
        entry = next(item for item in blocked["source"]["head"]["treePaths"] if item["path"] == ".env")
        review = tmp / "review.json"
        review.write_text(json.dumps({
            "schema": "compfuzor.archive-path-review/v1",
            "manifestSha256": blocked["headManifestSha256"],
            "included": [{**entry, "classification": "credential",
                          "decision": "local-custody-approved", "reason": "local private custody"}],
            "stagedVsUnstaged": None,
        }))
        reviewed = (*args, "--path-review", str(review))
        assert success_json(invoke(tmp, "adopt", *reviewed, "--json"))["state"] == "ready"
        (source / ".env").write_text("PRIVATE=changed\n")
        stale = success_json(invoke(tmp, "adopt", *reviewed, "--json"))
        assert stale["state"] == "blocked"
        assert any("review" in issue["code"] for issue in stale["blockers"])
        failure(invoke(tmp, "adopt", *reviewed, "--apply", "--json"))
        assert not list(tmp.glob(".compfuzor-adoptions/**/source.bundle"))
        missing = tmp / "uninitialized"
        missing_args = tuple(str(missing) if value == str(dest) else value for value in args)
        blocked_missing = success_json(invoke(tmp, "adopt", *missing_args, "--json"))
        assert any(item["code"] == "destination-missing" for item in blocked_missing["blockers"])
        human = invoke(tmp, "adopt", *missing_args)
        assert human.returncode == 0 and "refresh" in human.stdout and "BLOCKER" in human.stdout
        assert not missing.exists()
