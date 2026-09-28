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
CLIENT_ENV_MODULE = ROOT / "files/opencode/opencode-client-env.zsh"
LEGACY_WRAPPER = ROOT / "files/opencode/opencode-service.zsh"
LAST_CLIENT = ROOT / "files/opencode/opencode-last"
TEST_PASSWORD = "test-only-opencode-password"


def fake_binary(directory: Path, name: str = "opencode") -> Path:
    binary = directory / name
    binary.write_text(
        """#!/bin/bash
printf '%s\\0' "$@" > "$OPENCODE_TEST_ARGS"
printf '%s' "${OPENCODE_PASSWORD:-}" > "$OPENCODE_TEST_PASSWORD"
printf '%s' "$0" > "$OPENCODE_TEST_BINARY"
printf '%s' "${OPENCODE_ARGS:-}" > "$OPENCODE_TEST_OPENCODE_ARGS"
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
            "OPENCODE_TEST_BINARY": str(directory / "binary-capture"),
            "OPENCODE_TEST_OPENCODE_ARGS": str(directory / "opencode-args-capture"),
        }
    )
    env["PATH"] = f"{directory}:{env.get('PATH', '')}"
    env.pop("OPENCODE_PASSWORD", None)
    env.pop("OPENCODE_ARGS", None)
    return env


def captured_arguments(directory: Path) -> list[str]:
    data = (directory / "args").read_bytes()
    return [part.decode() for part in data.split(b"\0") if part]


def run_zim(env: dict[str, str], command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "zsh",
            "-c",
            f"source {shlex.quote(str(CLIENT_ENV_MODULE))}; source {shlex.quote(str(LEGACY_WRAPPER))}; {command}",
        ],
        cwd=ROOT,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


def run_client_env(env: dict[str, str], command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["zsh", "-c", f"source {shlex.quote(str(CLIENT_ENV_MODULE))}; {command}"],
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
    expected_opencode_args: str = "",
) -> None:
    result = run_zim(env, command)
    if result.returncode != 0:
        raise AssertionError(f"ZIM command failed:\n{result.stdout}{result.stderr}")
    actual = captured_arguments(directory)
    if actual != expected:
        raise AssertionError(f"{command!r}: expected {expected!r}, got {actual!r}")
    captured_password = (directory / "password-capture").read_text(encoding="utf-8")
    if captured_password != TEST_PASSWORD:
        raise AssertionError("ZIM module did not export the password file value")
    captured_opencode_args = (directory / "opencode-args-capture").read_text(encoding="utf-8")
    if captured_opencode_args != expected_opencode_args:
        raise AssertionError(
            f"expected OPENCODE_ARGS={expected_opencode_args!r}, got {captured_opencode_args!r}"
        )


def test_native_client_env_without_routing_functions() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-client-env-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env = capture_env(directory, binary, password_file)

        result = run_client_env(
            env,
            '(( ${+functions[opencode]} == 0 && ${+functions[opencode2]} == 0 )) || exit 10; "$OPENCODE_BINARY" models',
        )
        if result.returncode != 0:
            raise AssertionError(f"native client env module call failed:\n{result.stdout}{result.stderr}")
        if captured_arguments(directory) != ["models"]:
            raise AssertionError(f"client env module rewrote argv: {captured_arguments(directory)!r}")
        if (directory / "opencode-args-capture").read_text(encoding="utf-8") != "--server http://127.0.0.1:49373":
            raise AssertionError("client env module did not export the native OPENCODE_ARGS default")
        if (directory / "password-capture").read_text(encoding="utf-8") != TEST_PASSWORD:
            raise AssertionError("client env module did not export the credential")


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
            'export OPENCODE_ARGS="--server http://client-args.test"; opencode2 api get /api/health',
            ["api", "--server", "http://client-args.test", "get", "/api/health"],
        )
        assert_fake_call(
            directory,
            env,
            "opencode api --server http://example.test get /api/health",
            ["api", "--server", "http://example.test", "get", "/api/health"],
        )
        assert_fake_call(
            directory,
            env | {"OPENCODE_ARGS": ""},
            "opencode2 --standalone",
            ["--standalone"],
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
        assert_fake_call(
            directory,
            env,
            "opencode2 /workspace",
            ["--server", "http://127.0.0.1:49373", "/workspace"],
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


def test_last_client_lists_and_runs_newest_snapshot_with_server() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-last-") as temporary:
        directory = Path(temporary)
        older = fake_binary(directory, "opencode-202609221135")
        newer = fake_binary(directory, "opencode-20260923161000")
        fake_binary(directory, "opencode-backup")
        (directory / "opencode-20260924").write_text("not executable", encoding="utf-8")
        env = capture_env(directory, older, directory / "OPENCODE_PASSWORD")
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env.update(
            {
                "OPENCODE_SNAPSHOT_DIR": str(directory),
                "OPENCODE_CLIENT_ENV_MODULE": str(CLIENT_ENV_MODULE),
                "OPENCODE_PASSWORD": "stale-primary-password",
            }
        )

        listed = subprocess.run(
            [str(LAST_CLIENT), "list"],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        expected_list = f"{newer}\n{older}\n"
        if listed.returncode != 0 or listed.stdout != expected_list:
            raise AssertionError(
                f"expected newest-first snapshot list {expected_list!r}, "
                f"got {listed.returncode}: {listed.stdout!r}{listed.stderr}"
            )

        result = subprocess.run(
            [str(LAST_CLIENT), "api", "get", "/api/health"],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise AssertionError(f"opencode-last failed:\n{result.stdout}{result.stderr}")
        expected_args = ["api", "get", "/api/health"]
        if captured_arguments(directory) != expected_args:
            raise AssertionError(f"expected {expected_args!r}, got {captured_arguments(directory)!r}")
        if Path((directory / "binary-capture").read_text(encoding="utf-8")) != newer:
            raise AssertionError("opencode-last did not execute the newest dated client")
        expected_server_args = "--server http://127.0.0.1:49373"
        if (directory / "opencode-args-capture").read_text(encoding="utf-8") != expected_server_args:
            raise AssertionError("opencode-last did not set the native server-argument default")
        if (directory / "password-capture").read_text(encoding="utf-8") != TEST_PASSWORD:
            raise AssertionError("opencode-last did not load the configured client password")

        port_env = env | {
            "OPENCODE_SERVER_URL": "",
            "OPENCODE_SERVER_PORT": "49888",
        }
        port_result = subprocess.run(
            [str(LAST_CLIENT), "api", "get", "/api/health"],
            cwd=ROOT,
            env=port_env,
            check=False,
            capture_output=True,
            text=True,
        )
        if port_result.returncode != 0:
            raise AssertionError(f"opencode-last port fallback failed:\n{port_result.stdout}{port_result.stderr}")
        expected_port_args = ["api", "get", "/api/health"]
        if captured_arguments(directory) != expected_port_args:
            raise AssertionError(f"expected {expected_port_args!r}, got {captured_arguments(directory)!r}")
        if (directory / "opencode-args-capture").read_text(encoding="utf-8") != "--server http://127.0.0.1:49888":
            raise AssertionError("opencode-last did not derive native args from the overridden port")


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
                "OPENCODE_SERVE_ARGS": "--hostname 0.0.0.0 --port 49373",
            }
        )

        result = subprocess.run(
            ["bash", "-x", str(LAUNCHER)],
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
        if TEST_PASSWORD in result.stderr:
            raise AssertionError("password leaked to xtrace output")
        captured_password = (directory / "password-capture").read_text(encoding="utf-8")
        if captured_password != TEST_PASSWORD:
            raise AssertionError("launcher did not export the systemd credential")


def test_launcher_word_splits_baked_serve_args() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env = capture_env(directory, binary, password_file)
        env.update(
            {
                "CREDENTIALS_DIRECTORY": str(directory),
                "OPENCODE_SERVE_ARGS": (
                    "--hostname 0.0.0.0 --port 49373 "
                    "--cors http://workhorse.local:49373 "
                    "--cors http://workhorse.tail177464.ts.net:49373"
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


def test_launcher_fails_without_baked_serve_args() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-serve-") as temporary:
        directory = Path(temporary)
        binary = fake_binary(directory)
        password_file = directory / "OPENCODE_PASSWORD"
        password_file.write_text(TEST_PASSWORD, encoding="utf-8")
        env = capture_env(directory, binary, password_file)
        env.update({"CREDENTIALS_DIRECTORY": str(directory)})
        env.pop("OPENCODE_SERVE_ARGS", None)

        result = subprocess.run(
            ["bash", str(LAUNCHER)],
            cwd=ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

        if result.returncode == 0:
            raise AssertionError("launcher succeeded without baked serve arguments")
        if "OPENCODE_SERVE_ARGS is not set" not in result.stderr:
            raise AssertionError(f"missing bake did not fail clearly:\n{result.stdout}{result.stderr}")
        if (directory / "args").exists():
            raise AssertionError("server executed despite missing baked serve arguments")


if __name__ == "__main__":
    test_native_client_env_without_routing_functions()
    test_zim_routes_without_lifecycle_management()
    test_zim_fails_before_execution_without_password()
    test_last_client_lists_and_runs_newest_snapshot_with_server()
    test_launcher_reads_systemd_credential_without_argv_leak()
    test_launcher_word_splits_baked_serve_args()
    test_launcher_fails_without_baked_serve_args()
    print("ok: OpenCode foreground service and ZIM routing")
