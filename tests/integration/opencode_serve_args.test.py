#!/usr/bin/env python3
"""Verify build-env-serve-args.sh vector baking and in-place env rewriting."""

from __future__ import annotations

import atexit
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "files/opencode/build-env-serve-args.sh"

CORS_CSV = (
    "http://workhorse.local:49373,"
    "http://workhorse.lan:49373,"
    "http://workhorse.tail177464.ts.net:49373"
)
EXPECTED_VECTOR = (
    "--hostname 0.0.0.0 --port 49373 "
    "--cors http://workhorse.local:49373 "
    "--cors http://workhorse.lan:49373 "
    "--cors http://workhorse.tail177464.ts.net:49373"
)


def write_fixture(work: Path, include_key: bool, include_export: bool = True) -> None:
    lines = [
        'DIR="/tmp/opencode-serve-args-fixture"',
        'OPENCODE_SERVER_HOSTNAME="0.0.0.0"',
        'OPENCODE_SERVER_PORT="49373"',
        f'OPENCODE_SERVER_CORS="{CORS_CSV}"',
    ]
    if include_key:
        lines.append('OPENCODE_SERVE_ARGS="--hostname 127.0.0.1 --port 1"')
    (work / "env").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if include_export:
        (work / "env.export").write_text(
            "\n".join(f"export {line}" for line in lines) + "\n", encoding="utf-8"
        )


_rendered: Path | None = None


def rendered_baker() -> Path:
    """Render the Jinja source through Ansible once; return the bash path.

    Bin sources deploy via lookup('template'), so they may contain Jinja
    escapes that raw bash cannot parse. Tests execute the rendered
    artifact -- the same bytes that land in bin/.
    """
    global _rendered
    if _rendered is not None:
        return _rendered
    directory = tempfile.mkdtemp(prefix="compfuzor-opencode-serve-args-render-")
    atexit.register(shutil.rmtree, directory, ignore_errors=True)
    rendered = Path(directory) / "build-env-serve-args.sh"
    playbook = ROOT / ".test-agent-opencode-serve-args-render.pb"
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  tasks:
    - copy:
        dest: {str(rendered)!r}
        content: "{{{{ lookup('template', 'files/opencode/build-env-serve-args.sh') }}}}"
""",
        encoding="utf-8",
    )
    try:
        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        result = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
            cwd=ROOT,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
    finally:
        playbook.unlink(missing_ok=True)
    if result.returncode != 0:
        raise AssertionError(f"bin render failed:\n{result.stdout}{result.stderr}")
    syntax = subprocess.run(
        ["bash", "-n", str(rendered)], check=False, capture_output=True, text=True
    )
    if syntax.returncode != 0:
        raise AssertionError(f"rendered script is not valid bash:\n{syntax.stderr}")
    _rendered = rendered
    return rendered


def run_baker(work: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["DIR"] = str(work)
    env["OPENCODE_SERVER_HOSTNAME"] = "0.0.0.0"
    env["OPENCODE_SERVER_PORT"] = "49373"
    env["OPENCODE_SERVER_CORS"] = CORS_CSV
    return subprocess.run(
        ["bash", str(rendered_baker())],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def check_result(result: subprocess.CompletedProcess[str], label: str) -> None:
    if result.returncode != 0:
        raise AssertionError(f"{label} failed:\n{result.stdout}{result.stderr}")


def test_bakes_vector_replacing_stale_value_idempotently() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-args-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir()
        write_fixture(work, include_key=True)

        first = run_baker(work)
        check_result(first, "replacement run")

        env_text = (work / "env").read_text(encoding="utf-8")
        export_text = (work / "env.export").read_text(encoding="utf-8")
        expected_env_line = f'OPENCODE_SERVE_ARGS="{EXPECTED_VECTOR}"'
        expected_export_line = f'export OPENCODE_SERVE_ARGS="{EXPECTED_VECTOR}"'
        if env_text.count(expected_env_line) != 1:
            raise AssertionError(f"env line wrong or duplicated:\n{env_text}")
        if export_text.count(expected_export_line) != 1:
            raise AssertionError(f"env.export line wrong or duplicated:\n{export_text}")
        if 'OPENCODE_SERVE_ARGS="--hostname 127.0.0.1' in env_text + export_text:
            raise AssertionError("stale vector survived the rewrite")
        if 'OPENCODE_SERVER_CORS="' not in env_text:
            raise AssertionError(f"input env lines were not preserved:\n{env_text}")
        if EXPECTED_VECTOR not in first.stdout:
            raise AssertionError(f"run did not report the vector:\n{first.stdout}")

        second = run_baker(work)
        check_result(second, "idempotent run")
        if (work / "env").read_text(encoding="utf-8") != env_text:
            raise AssertionError("second run drifted the env file")
        if (work / "env.export").read_text(encoding="utf-8") != export_text:
            raise AssertionError("second run drifted env.export")


def test_appends_when_key_missing() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-args-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir()
        write_fixture(work, include_key=False)

        result = run_baker(work)
        check_result(result, "append run")

        env_text = (work / "env").read_text(encoding="utf-8")
        export_text = (work / "env.export").read_text(encoding="utf-8")
        if f'OPENCODE_SERVE_ARGS="{EXPECTED_VECTOR}"' not in env_text:
            raise AssertionError(f"env line was not appended:\n{env_text}")
        if f'export OPENCODE_SERVE_ARGS="{EXPECTED_VECTOR}"' not in export_text:
            raise AssertionError(f"env.export line was not appended:\n{export_text}")


def test_empty_cors_bakes_hostname_and_port_only() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-args-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir()
        write_fixture(work, include_key=False)
        (work / "env").write_text(
            (work / "env").read_text(encoding="utf-8").replace(
                f'OPENCODE_SERVER_CORS="{CORS_CSV}"', 'OPENCODE_SERVER_CORS=""'
            ),
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["DIR"] = str(work)
        env["OPENCODE_SERVER_HOSTNAME"] = "0.0.0.0"
        env["OPENCODE_SERVER_PORT"] = "49373"
        env["OPENCODE_SERVER_CORS"] = ""
        result = subprocess.run(
            ["bash", str(rendered_baker())],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        check_result(result, "empty cors run")

        env_text = (work / "env").read_text(encoding="utf-8")
        expected = 'OPENCODE_SERVE_ARGS="--hostname 0.0.0.0 --port 49373"'
        if env_text.count(expected) != 1:
            raise AssertionError(f"expected hostname/port-only vector:\n{env_text}")
        if "--cors" in env_text:
            raise AssertionError(f"cors flags leaked into the empty-cors vector:\n{env_text}")


def test_missing_required_inputs_fail_loudly() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-args-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir()
        write_fixture(work, include_key=False)

        for missing in ("OPENCODE_SERVER_HOSTNAME", "OPENCODE_SERVER_PORT"):
            env = os.environ.copy()
            env["DIR"] = str(work)
            env["OPENCODE_SERVER_HOSTNAME"] = "0.0.0.0"
            env["OPENCODE_SERVER_PORT"] = "49373"
            env["OPENCODE_SERVER_CORS"] = CORS_CSV
            env.pop(missing, None)
            result = subprocess.run(
                ["bash", str(rendered_baker())],
                cwd=ROOT,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                raise AssertionError(f"bake succeeded without {missing}")
            if missing not in result.stderr:
                raise AssertionError(
                    f"missing {missing} did not fail clearly:\n{result.stdout}{result.stderr}"
                )
            if "OPENCODE_SERVE_ARGS=" in (work / "env").read_text(encoding="utf-8"):
                raise AssertionError("failed run still rewrote the vector")


def test_tolerates_missing_env_export() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-args-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir()
        write_fixture(work, include_key=False, include_export=False)

        result = run_baker(work)
        check_result(result, "missing env.export run")
        if f'OPENCODE_SERVE_ARGS="{EXPECTED_VECTOR}"' not in (work / "env").read_text(
            encoding="utf-8"
        ):
            raise AssertionError("env was not updated when env.export was absent")


if __name__ == "__main__":
    test_bakes_vector_replacing_stale_value_idempotently()
    test_appends_when_key_missing()
    test_empty_cors_bakes_hostname_and_port_only()
    test_missing_required_inputs_fail_loudly()
    test_tolerates_missing_env_export()
    print("ok: OpenCode serve argument vector baking")
