#!/usr/bin/env python3
"""Verify build-env-cors.sh discovery and in-place env rewriting."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
DISCOVERY = ROOT / "files/opencode/build-env-cors.sh"

EXPECTED_CSV = ",".join(
    [
        "http://workhorse.local:49373",
        "http://workhorse.lan:49373",
        "http://workhorse.hosts.voodoowarez.com:49373",
        "http://workhorse.tail177464.ts.net:49373",
    ]
)
HOSTNAME_A = (
    "workhorse.lan workhorse.hosts.voodoowarez.com "
    "workhorse.tail177464.ts.net workhorse.lan"
)


def write_hostname_shim(shims: Path, all_names: str) -> None:
    shim = shims / "hostname"
    shim.write_text(
        "#!/bin/sh\n"
        'case "$1" in\n'
        "  -s) printf '%s\\n' workhorse ;;\n"
        f"  -A) printf '%s\\n' \"{all_names}\" ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    shim.chmod(0o755)


def write_fixture(work: Path, include_key: bool, include_export: bool = True) -> None:
    lines = [
        'DIR="/tmp/opencode-cors-fixture"',
        'OPENCODE_SERVER_PORT="49373"',
    ]
    if include_key:
        lines.append('OPENCODE_SERVER_CORS="http://stale.example:49373"')
    (work / "env").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if include_export:
        (work / "env.export").write_text(
            "\n".join(f"export {line}" for line in lines) + "\n", encoding="utf-8"
        )


def run_discovery(shims: Path, work: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PATH"] = f"{shims}:{env['PATH']}"
    env["DIR"] = str(work)
    env["OPENCODE_SERVER_PORT"] = "49373"
    return subprocess.run(
        ["bash", str(DISCOVERY)],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def check_result(result: subprocess.CompletedProcess[str], label: str) -> None:
    if result.returncode != 0:
        raise AssertionError(f"{label} failed:\n{result.stdout}{result.stderr}")


def test_replaces_stale_value_in_both_files_and_is_idempotent() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-cors-") as temporary:
        root = Path(temporary)
        shims, work = root / "shims", root / "work"
        shims.mkdir()
        work.mkdir()
        write_hostname_shim(shims, HOSTNAME_A)
        write_fixture(work, include_key=True)

        first = run_discovery(shims, work)
        check_result(first, "replacement run")

        env_text = (work / "env").read_text(encoding="utf-8")
        export_text = (work / "env.export").read_text(encoding="utf-8")
        expected_env_line = f'OPENCODE_SERVER_CORS="{EXPECTED_CSV}"'
        expected_export_line = f'export OPENCODE_SERVER_CORS="{EXPECTED_CSV}"'
        if env_text.count(expected_env_line) != 1:
            raise AssertionError(f"env line wrong or duplicated:\n{env_text}")
        if export_text.count(expected_export_line) != 1:
            raise AssertionError(f"env.export line wrong or duplicated:\n{export_text}")
        if 'OPENCODE_SERVER_CORS="http://stale.example' in env_text + export_text:
            raise AssertionError("stale origin survived the rewrite")
        if 'DIR="/tmp/opencode-cors-fixture"' not in env_text:
            raise AssertionError(f"unrelated env lines were not preserved:\n{env_text}")
        if EXPECTED_CSV not in first.stdout:
            raise AssertionError(f"run did not report origins:\n{first.stdout}")

        second = run_discovery(shims, work)
        check_result(second, "idempotent run")
        if (work / "env").read_text(encoding="utf-8") != env_text:
            raise AssertionError("second run drifted the env file")
        if (work / "env.export").read_text(encoding="utf-8") != export_text:
            raise AssertionError("second run drifted env.export")


def test_appends_when_key_missing() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-cors-") as temporary:
        root = Path(temporary)
        shims, work = root / "shims", root / "work"
        shims.mkdir()
        work.mkdir()
        write_hostname_shim(shims, HOSTNAME_A)
        write_fixture(work, include_key=False)

        result = run_discovery(shims, work)
        check_result(result, "append run")

        env_text = (work / "env").read_text(encoding="utf-8")
        export_text = (work / "env.export").read_text(encoding="utf-8")
        if f'OPENCODE_SERVER_CORS="{EXPECTED_CSV}"' not in env_text:
            raise AssertionError(f"env line was not appended:\n{env_text}")
        if f'export OPENCODE_SERVER_CORS="{EXPECTED_CSV}"' not in export_text:
            raise AssertionError(f"env.export line was not appended:\n{export_text}")


def test_hostname_a_without_names_yields_only_local_origin() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-cors-") as temporary:
        root = Path(temporary)
        shims, work = root / "shims", root / "work"
        shims.mkdir()
        work.mkdir()
        write_hostname_shim(shims, "")
        write_fixture(work, include_key=False)

        result = run_discovery(shims, work)
        check_result(result, "local-only run")

        env_text = (work / "env").read_text(encoding="utf-8")
        expected = 'OPENCODE_SERVER_CORS="http://workhorse.local:49373"'
        if env_text.count(expected) != 1:
            raise AssertionError(f"expected only the .local origin:\n{env_text}")


def test_tolerates_missing_env_export() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-cors-") as temporary:
        root = Path(temporary)
        shims, work = root / "shims", root / "work"
        shims.mkdir()
        work.mkdir()
        write_hostname_shim(shims, HOSTNAME_A)
        write_fixture(work, include_key=False, include_export=False)

        result = run_discovery(shims, work)
        check_result(result, "missing env.export run")
        if f'OPENCODE_SERVER_CORS="{EXPECTED_CSV}"' not in (work / "env").read_text(
            encoding="utf-8"
        ):
            raise AssertionError("env was not updated when env.export was absent")


if __name__ == "__main__":
    test_replaces_stale_value_in_both_files_and_is_idempotent()
    test_appends_when_key_missing()
    test_hostname_a_without_names_yields_only_local_origin()
    test_tolerates_missing_env_export()
    print("ok: OpenCode CORS origin discovery and env rewrite")
