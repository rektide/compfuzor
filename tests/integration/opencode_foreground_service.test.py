#!/usr/bin/env python3
"""Verify OpenCode foreground launch and ZIM explicit-server routing."""

from __future__ import annotations

import os
from pathlib import Path
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "files/opencode/serve.sh"
ZIM_MODULE = ROOT / "files/opencode/opencode-service.zsh"
TEST_PASSWORD = "test-only-opencode-password"


def fake_binary(directory: Path) -> Path:
    binary = directory / "opencode2"
    binary.write_text(
        """#!/bin/bash
printf '%s\\0' "$@" > "$OPENCODE_TEST_ARGS"
printf '%s' "${OPENCODE_PASSWORD:-}" > "$OPENCODE_TEST_PASSWORD"
""",
        encoding="utf-8",
    )
    binary.chmod(0o755)
    return binary


def capture_env(directory: Path, binary: Path, password_file: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "OPENCODE_BINARY": str(binary),
            "OPENCODE_PASSWORD_FILE": str(password_file),
            "OPENCODE_SERVER_URL": "http://127.0.0.1:49373",
            "OPENCODE_TEST_ARGS": str(directory / "args"),
            "OPENCODE_TEST_PASSWORD": str(directory / "password-capture"),
        }
    )
    env.pop("OPENCODE_PASSWORD", None)
    return env


def captured_arguments(directory: Path) -> list[str]:
    data = (directory / "args").read_bytes()
    return [part.decode() for part in data.split(b"\0") if part]


def run_zim(env: dict[str, str], command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["zsh", "-c", f"source {shlex.quote(str(ZIM_MODULE))}; {command}"],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def assert_fake_call(
    directory: Path,
    env: dict[str, str],
    command: str,
    expected: list[str],
) -> None:
    result = run_zim(env, command)
    if result.returncode != 0:
        raise AssertionError(f"ZIM command failed:\n{result.stdout}{result.stderr}")
    actual = captured_arguments(directory)
    if actual != expected:
        raise AssertionError(f"{command!r}: expected {expected!r}, got {actual!r}")
    captured_password = (directory / "password-capture").read_text(encoding="utf-8")
    if captured_password != TEST_PASSWORD:
        raise AssertionError("ZIM wrapper did not export the password file value")


def test_zim_routes_without_lifecycle_management() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-zim-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env = capture_env(directory, binary, password_file)

        assert_fake_call(
            directory,
            env,
            "opencode2 models",
            ["models", "--server", "http://127.0.0.1:49373"],
        )
        assert_fake_call(
            directory,
            env,
            "opencode2 --log-level info api get /api/health",
            [
                "--log-level",
                "info",
                "api",
                "--server",
                "http://127.0.0.1:49373",
                "get",
                "/api/health",
            ],
        )
        assert_fake_call(
            directory,
            env,
            "opencode2 auth list --format json",
            [
                "auth",
                "list",
                "--server",
                "http://127.0.0.1:49373",
                "--format",
                "json",
            ],
        )
        assert_fake_call(directory, env, "opencode service status", ["service", "status"])
        assert_fake_call(directory, env, "opencode2 mcp list", ["mcp", "list"])
        assert_fake_call(directory, env, "opencode2 --standalone", ["--standalone"])
        assert_fake_call(
            directory,
            env,
            "opencode2 /workspace",
            ["--server", "http://127.0.0.1:49373", "/workspace"],
        )
        assert_fake_call(
            directory,
            env,
            "opencode api --server http://example.test get /api/health",
            ["api", "--server", "http://example.test", "get", "/api/health"],
        )


def test_zim_fails_before_execution_without_password() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-zim-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        env = capture_env(directory, binary, directory / "missing")

        result = run_zim(env, "opencode2 models")

        if result.returncode != 1 or "OPENCODE_PASSWORD was not loaded" not in result.stderr:
            raise AssertionError(f"missing password did not fail clearly:\n{result.stdout}{result.stderr}")
        if (directory / "args").exists():
            raise AssertionError("client executed despite a missing managed password")

        fallback = run_zim(env, "opencode2 service status")
        if fallback.returncode != 0:
            raise AssertionError(f"fallback command required managed password:\n{fallback.stderr}")
        if captured_arguments(directory) != ["service", "status"]:
            raise AssertionError("fallback command was not passed through unchanged")


def test_launcher_reads_systemd_credential_without_argv_leak() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env = capture_env(directory, binary, password_file)
        env.update(
            {
                "CREDENTIALS_DIRECTORY": str(directory),
                "OPENCODE_SERVER_HOSTNAME": "0.0.0.0",
                "OPENCODE_SERVER_PORT": "49373",
            }
        )

        result = subprocess.run(
            ["bash", str(LAUNCHER)],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise AssertionError(f"foreground launcher failed:\n{result.stdout}{result.stderr}")
        arguments = captured_arguments(directory)
        expected = ["serve", "--hostname", "0.0.0.0", "--port", "49373"]
        if arguments != expected:
            raise AssertionError(f"expected {expected!r}, got {arguments!r}")
        if TEST_PASSWORD in arguments:
            raise AssertionError("password leaked into the server argument vector")
        captured_password = (directory / "password-capture").read_text(encoding="utf-8")
        if captured_password != TEST_PASSWORD:
            raise AssertionError("launcher did not export the systemd credential")


def test_launcher_expands_cors_origins_into_repeatable_flags() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env = capture_env(directory, binary, password_file)
        env.update(
            {
                "CREDENTIALS_DIRECTORY": str(directory),
                "OPENCODE_SERVER_HOSTNAME": "0.0.0.0",
                "OPENCODE_SERVER_PORT": "49373",
                "OPENCODE_SERVER_CORS": (
                    "http://workhorse.local:49373,"
                    "http://workhorse.tail177464.ts.net:49373"
                ),
            }
        )

        result = subprocess.run(
            ["bash", str(LAUNCHER)],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise AssertionError(f"foreground launcher failed:\n{result.stdout}{result.stderr}")
        arguments = captured_arguments(directory)
        expected = [
            "serve",
            "--hostname",
            "0.0.0.0",
            "--port",
            "49373",
            "--cors",
            "http://workhorse.local:49373",
            "--cors",
            "http://workhorse.tail177464.ts.net:49373",
        ]
        if arguments != expected:
            raise AssertionError(f"expected {expected!r}, got {arguments!r}")


if __name__ == "__main__":
    test_zim_routes_without_lifecycle_management()
    test_zim_fails_before_execution_without_password()
    test_launcher_reads_systemd_credential_without_argv_leak()
    test_launcher_expands_cors_origins_into_repeatable_flags()
    print("ok: OpenCode foreground service and ZIM routing")
