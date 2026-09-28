#!/usr/bin/env python3
"""Verify per-instance rendering of opencode.src.pb.

Runs the real playbook with the local connector into throwaway fixture roots
(DIR/ETCS_DIR/GLOBAL_BINS_DIR/PASSWORDS_DIR redirected under a temp dir) with
every effectful subsystem bypassed: no packages, no repo checkout, no unit
installation or thunk, no bin execution, no links into the real
/usr/local/bin or user config. Assertions cover the derived naming contract,
the fail-closed port guard, presence-gated env keys, the primary
compatibility render, and the secondary launcher's argv routing against a
fake client binary.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
PLAYBOOK = ROOT / "opencode.src.pb"
TEST_PASSWORD = "test-only-opencode-instance-password"

# BINS stay enabled (the fixture asserts on rendered bin scripts); everything
# that would touch the live system is off or redirected: unit generation needs
# SYSTEMD_INSTALL active, so the unit directories point into the fixture and
# the install bins never execute.
BYPASSES = {
    "PKGS_BYPASS": True,
    "APT_BYPASS": True,
    "MODULES_BYPASS": True,
    "REPO_BYPASS": True,
    "GIT_BYPASS": True,
    "SYSTEMD_THUNK_BYPASS": True,
    "BINS_RUN_BYPASS": True,
    "GLOBAL_BINS_BYPASS": True,
    "LINKS_BYPASS": True,
}


def run_playbook(extra: dict[str, str], expect_failure: bool = False):
    env = os.environ.copy()
    env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
    command = ["ansible-playbook", "-i", "localhost,", "-c", "local", str(PLAYBOOK)]
    for key, value in {**BYPASSES, **extra}.items():
        command += ["-e", f"{key}={value}"]
    result = subprocess.run(command, cwd=ROOT, env=env, check=False, text=True, capture_output=True)
    if expect_failure:
        if result.returncode == 0:
            raise AssertionError(f"expected playbook failure, it passed:\n{result.stdout}")
        return result
    if result.returncode != 0:
        raise AssertionError(f"playbook failed:\n{result.stdout}\n{result.stderr}")
    return result


def roots(fixture: Path, instance: str) -> dict[str, str]:
    return {
        "SRCS_DIR": str(fixture / "src"),
        "OPTS_DIR": str(fixture / "opts"),
        "ETCS_DIR": str(fixture / "etc-opt"),
        "GLOBAL_BINS_DIR": str(fixture / "global-bins"),
        "PASSWORDS_DIR": str(fixture / "config" / f"opencode-{instance}" / "secrets"),
        "SYSTEMD_USER_UNIT_DIR": str(fixture / "units" / "user"),
        "SYSTEMD_SYSTEM_UNIT_DIR": str(fixture / "units" / "system"),
    }


def deployment_of(fixture: Path, instance: str) -> Path:
    return fixture / "src" / f"opencode-{instance}"


def etc_of(fixture: Path, instance: str) -> Path:
    return fixture / "etc-opt" / f"opencode-{instance}"


def render(fixture: Path, instance: str, extra: dict[str, str] | None = None) -> Path:
    run_playbook({**roots(fixture, instance), "INSTANCE": instance, **(extra or {})})
    return deployment_of(fixture, instance)


def require_file(path: Path, label: str) -> str:
    if not path.is_file():
        raise AssertionError(f"expected {label} missing: {path}")
    return path.read_text(encoding="utf-8")


def find_unit(etc: Path, filename: str) -> Path:
    matches = sorted(etc.rglob(filename))
    if not matches:
        raise AssertionError(
            f"no generated {filename} under {etc}: "
            f"{[str(p) for p in etc.rglob('*')] if etc.exists() else 'etc missing'}"
        )
    return matches[0]


def test_primary_render_is_unchanged(fixture: Path) -> None:
    deployment = render(fixture, "git")
    etc = etc_of(fixture, "git")
    env = require_file(deployment / "env", "primary env")
    for expected in (
        'OPENCODE_SERVER_HOSTNAME="0.0.0.0"',
        'OPENCODE_SERVER_PORT="49373"',
        'OPENCODE_SERVER_URL="http://127.0.0.1:49373"',
        f'OPENCODE_PASSWORD_FILE="{fixture}/config/opencode-git/secrets/OPENCODE_PASSWORD"',
        f'OPENCODE_WORKING_DIR="{Path.home()}/src/opencode-working"',
    ):
        if expected not in env:
            raise AssertionError(f"primary env lost {expected!r}:\n{env}")
    for forbidden in (
        "OPENCODE_BINARY=",
        "OPENCODE_CONFIG_DIR=",
        "OPENCODE_DB=",
        "OPENCODE_CLIENT_ENV_MODULE=",
    ):
        if forbidden in env:
            raise AssertionError(f"primary env gained presence-gated key {forbidden!r}:\n{env}")

    service = require_file(etc / "opencode.service", "primary service unit")
    for expected in (
        "Description=OpenCode V2 operator-managed foreground server",
        "SyslogIdentifier=opencode",
        f"ExecStart={deployment}/bin/serve.sh",
        f"EnvironmentFile=-{deployment}/env",
    ):
        if expected not in service:
            raise AssertionError(f"primary unit lost {expected!r}:\n{service}")
    if not (etc / "opencode-cleanup.timer").is_file():
        raise AssertionError("primary cleanup timer missing")

    restart = require_file(deployment / "bin" / "restart.sh", "primary restart.sh")
    if "${OPENCODE_UNIT:-opencode.service}" not in restart:
        raise AssertionError(f"primary restart.sh lost the opencode.service default:\n{restart}")
    for expected in ('"$_url/api/info"', 'user = "opencode:%s"', "_password_file="):
        if expected not in restart:
            raise AssertionError(f"primary restart.sh missing authenticated readiness check {expected!r}:\n{restart}")
    subprocess.run(["bash", "-n", str(deployment / "bin" / "restart.sh")], check=True)

    install = require_file(deployment / "bin" / "install.sh", "primary install.sh")
    for expected in ("$GLOBAL_BINS_DIR/opencode\n", "$GLOBAL_BINS_DIR/opencode2-node\n"):
        if expected not in install:
            raise AssertionError(f"primary install.sh lost unsuffixed link {expected!r}:\n{install}")

    module = require_file(etc / "zim-modules" / "opencode-client-args" / "init.zsh", "primary client-env ZIM module")
    for expected in (
        'export OPENCODE_ARGS="--server ${OPENCODE_SERVER_URL:?OPENCODE_SERVER_URL is not set}"',
        "export OPENCODE_PASSWORD",
    ):
        if expected not in module:
            raise AssertionError(f"primary ZIM module missing {expected!r}:\n{module}")
    if (etc / "zim-modules" / "opencode-service").exists():
        raise AssertionError("legacy shell wrapper was loaded as an active ZIM module")
    retired_wrapper = require_file(
        etc / "zim" / "zimrc" / "active" / "55-opencode-service.conf",
        "legacy wrapper import tombstone",
    )
    if "zmodule" in retired_wrapper:
        raise AssertionError(f"legacy shell wrapper remains imported:\n{retired_wrapper}")

    serve = require_file(deployment / "bin" / "serve.sh", "systemd serve launcher")
    for expected in ("OPENCODE_SERVE_ARGS", '"${serve_argv[@]}"'):
        if expected not in serve:
            raise AssertionError(f"serve.sh lost service behavior {expected!r}:\n{serve}")
    if "CREDENTIALS_DIRECTORY" in serve:
        raise AssertionError("interim launcher still requires the systemd credential")
    for forbidden in ("# guard helper:", "COMPFUZOR_OPENCODE_BYPASS", "env helper:", "# loud helper:"):
        if forbidden in serve:
            raise AssertionError(f"systemd serve launcher retained generic bin helper {forbidden!r}")
    subprocess.run(["bash", "-n", str(deployment / "bin" / "serve.sh")], check=True)

    require_file(deployment / "bin" / "opencode-last", "primary opencode-last")
    require_file(deployment / "bin" / "opencode-live", "primary opencode-live")
    require_file(deployment / "bin" / "opencode-instance", "shared launcher bin")
    print("ok: primary render preserves the historical surface")


def test_secondary_render(fixture: Path) -> None:
    deployment = render(fixture, "dev", {"OPENCODE_SERVER_PORT": "49381"})
    etc = etc_of(fixture, "dev")
    env = require_file(deployment / "env", "secondary env")
    for expected in (
        'OPENCODE_SERVER_HOSTNAME="127.0.0.1"',
        'OPENCODE_SERVER_PORT="49381"',
        'OPENCODE_SERVER_URL="http://127.0.0.1:49381"',
        f'OPENCODE_BINARY="{fixture}/global-bins/opencode-dev"',
        f'OPENCODE_CONFIG_DIR="{etc}"',
        'OPENCODE_DB="opencode-dev.db"',
        f'OPENCODE_CLIENT_ENV_MODULE="{etc}/client/client-env.zsh"',
        f'OPENCODE_WORKING_DIR="{Path.home()}/src/opencode-working-dev"',
        f'OPENCODE_PASSWORD_FILE="{fixture}/config/opencode-dev/secrets/OPENCODE_PASSWORD"',
    ):
        if expected not in env:
            raise AssertionError(f"secondary env missing {expected!r}:\n{env}")

    service = require_file(etc / "opencode-dev.service", "secondary service unit")
    for expected in ("SyslogIdentifier=opencode-dev", f"ExecStart={deployment}/bin/serve.sh"):
        if expected not in service:
            raise AssertionError(f"secondary unit missing {expected!r}:\n{service}")
    require_file(etc / "opencode-dev-cleanup.service", "secondary cleanup service")
    require_file(etc / "opencode-dev-cleanup.timer", "secondary cleanup timer")
    if (etc / "opencode.service").exists():
        raise AssertionError("secondary render emitted the primary unit name")

    restart = require_file(deployment / "bin" / "restart.sh", "secondary restart.sh")
    if "${OPENCODE_UNIT:-opencode-dev.service}" not in restart:
        raise AssertionError(f"secondary restart.sh unit default wrong:\n{restart}")

    install = require_file(deployment / "bin" / "install.sh", "secondary install.sh")
    for expected in ("$GLOBAL_BINS_DIR/opencode-dev\n", "$GLOBAL_BINS_DIR/opencode2-node-dev\n"):
        if expected not in install:
            raise AssertionError(f"secondary install.sh missing suffixed link {expected!r}:\n{install}")

    require_file(etc / "client" / "client-env.zsh", "secondary client-env module")
    if (etc / "zim-modules").exists():
        raise AssertionError("secondary render emitted ZIM modules")
    if (etc / "zim").exists():
        raise AssertionError("secondary render emitted ZIM fragments")
    # The primary-only interactive bins still render locally for secondaries
    # (their defaults target the primary deployment), but the launcher is the
    # secondary entrypoint.
    launcher = require_file(deployment / "bin" / "opencode-instance", "secondary launcher")

    status_proc = require_file(deployment / "bin" / "status-exe-current.sh", "exe-current reporter")
    if f"{fixture}/global-bins/opencode-dev" not in status_proc:
        raise AssertionError(f"secondary exe-current expects the wrong link:\n{status_proc}")

    install_user = require_file(deployment / "bin" / "install-user.sh", "secondary install-user.sh")
    if "ln -sv" in install_user:
        raise AssertionError(f"secondary install-user.sh must not touch the primary config link:\n{install_user}")

    readme = require_file(deployment / "README.md", "secondary README")
    for expected in ("opencode-dev.service", "opencode-dev api get /api/info"):
        if expected not in readme:
            raise AssertionError(f"secondary README missing {expected!r}:\n{readme}")
    print("ok: secondary render isolates names, env, units, and entrypoint")


def test_port_guard(fixture: Path) -> None:
    for extra, why in (
        ({}, "unset"),
        ({"OPENCODE_SERVER_PORT": "49373"}, "primary port"),
        ({"OPENCODE_SERVER_PORT": "49374"}, "upstream port"),
    ):
        result = run_playbook({**roots(fixture, "dev"), "INSTANCE": "dev", **extra}, expect_failure=True)
        if "OPENCODE_SERVER_PORT" not in result.stdout:
            raise AssertionError(f"port guard did not fail clearly for {why}:\n{result.stdout}")
    print("ok: secondary port selection fails closed")


def fake_client(directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / "opencode-dev"
    binary.write_text(
        "#!/bin/bash\n"
        'printf \'%s\\0\' "$@" > "$OPENCODE_TEST_ARGS"\n'
        'printf \'%s\' "${OPENCODE_PASSWORD:-}" > "$OPENCODE_TEST_PASSWORD"\n'
        'printf \'%s\' "${OPENCODE_CONFIG_DIR:-}" > "$OPENCODE_TEST_CONFIG_DIR"\n'
        'printf \'%s\' "${OPENCODE_DB:-}" > "$OPENCODE_TEST_DB"\n'
        'printf \'%s\' "${OPENCODE_ARGS:-}" > "$OPENCODE_TEST_OPENCODE_ARGS"\n',
        encoding="utf-8",
    )
    binary.chmod(0o755)
    return binary


def test_launcher_routes_instance(fixture: Path) -> None:
    deployment = render(fixture, "dev", {"OPENCODE_SERVER_PORT": "49381"})
    launcher = deployment / "bin" / "opencode-instance"
    work = fixture / "launcher-run"
    work.mkdir()
    fake_client(fixture / "global-bins")

    # The generated credential is authoritative: the playbook generated it
    # into the redirected PASSWORDS_DIR and env points at it.
    generated = (fixture / "config" / "opencode-dev" / "secrets" / "OPENCODE_PASSWORD").read_text(encoding="utf-8").strip()

    env = os.environ.copy()
    env.update(
        {
            "OPENCODE_TEST_ARGS": str(work / "args"),
            "OPENCODE_TEST_PASSWORD": str(work / "password-capture"),
            "OPENCODE_TEST_CONFIG_DIR": str(work / "config-dir-capture"),
            "OPENCODE_TEST_DB": str(work / "db-capture"),
            "OPENCODE_TEST_OPENCODE_ARGS": str(work / "opencode-args-capture"),
        }
    )
    env["OPENCODE_PASSWORD"] = "stale-primary-password"
    env.pop("OPENCODE_ARGS", None)

    for command, expected, args_override in (
        (["api", "get", "/api/info"], ["api", "get", "/api/info"], None),
        (["service", "status"], ["service", "status"], None),
        (["--standalone"], ["--standalone"], ""),
    ):
        command_env = env if args_override is None else env | {"OPENCODE_ARGS": args_override}
        result = subprocess.run(
            ["zsh", str(launcher), *command],
            cwd=ROOT,
            env=command_env,
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise AssertionError(f"launcher failed for {command}:\n{result.stdout}{result.stderr}")
        actual = [part.decode() for part in (work / "args").read_bytes().split(b"\0") if part]
        if actual != expected:
            raise AssertionError(f"{command}: expected {expected!r}, got {actual!r}")
        if (work / "password-capture").read_text(encoding="utf-8") != generated:
            raise AssertionError("launcher did not load the generated instance credential")
        if (work / "config-dir-capture").read_text(encoding="utf-8") != str(etc_of(fixture, "dev")):
            raise AssertionError("launcher did not export the instance config dir")
        if (work / "db-capture").read_text(encoding="utf-8") != "opencode-dev.db":
            raise AssertionError("launcher did not export the instance database")
        expected_server_args = args_override if args_override is not None else "--server http://127.0.0.1:49381"
        if (work / "opencode-args-capture").read_text(encoding="utf-8") != expected_server_args:
            raise AssertionError(
                f"launcher exported wrong OPENCODE_ARGS for {command}: expected {expected_server_args!r}"
            )
    print("ok: secondary launcher routes argv, credential, config, and db")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-opencode-instances-") as temporary:
        fixture = Path(temporary)
        test_port_guard(fixture)
        test_primary_render_is_unchanged(fixture)
        test_secondary_render(fixture)
        test_launcher_routes_instance(fixture)
    print("ok: OpenCode per-instance deployment")


if __name__ == "__main__":
    main()
