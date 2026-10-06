#!/usr/bin/env python3
"""Full inert Rust-storage renders and fake-tool runtime contract checks."""

from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

import pytest


ROOT = Path(__file__).resolve().parents[3]
SCRATCH = ROOT / ".test-agent" / "rust-storage"


def run(*command: str, cwd: Path, env: dict[str, str] | None = None,
        check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    if check and result.returncode:
        raise AssertionError(f"{command} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    return result


@pytest.fixture(scope="module")
def rendered():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        tmp = Path(directory)
        home = tmp / "home with spaces"
        home.mkdir()
        for name in ("src", "archive", ".config/mise", ".cargo"):
            (home / name).mkdir(parents=True)
        main_config = home / ".config/mise/config.toml"
        main_config.write_text('[tools]\nrust = "nightly"\n')
        cargo_config = home / ".cargo/config.toml"
        cargo_config.write_text('[build]\njobs = 2\n')
        fake = tmp / "fake mise"
        fake.write_text(f'#!{sys.executable}\n' + '''
import json, os, pathlib, sys
with open(os.environ["RUST_STORAGE_LOG"], "a") as log:
    log.write(json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(),
        "env": {k: os.environ.get(k) for k in
        ("MISE_AUTO_INSTALL", "MISE_EXEC_AUTO_INSTALL", "RUSTUP_AUTO_INSTALL")}}) + "\\n")
if sys.argv[1] == "where":
    print(os.environ["RUST_STORAGE_INSTALLED"])
elif sys.argv[1] == "exec":
    assert sys.argv[2] == "--"
    os.execv(sys.argv[3], sys.argv[3:])
''')
        fake.chmod(0o755)
        common = {
            "HOMEDIR": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "XDG_STATE_HOME": str(home / ".local/state"),
            "XDG_RUNTIME_DIR": str(home / "runtime"),
            "RUST_STORAGE_MISE_BIN": str(fake),
            "BINS_RUN_BYPASS": True,
            "BUILD_RUN_BYPASS": True,
            "PKGS_BYPASS": True,
            "APT_BYPASS": True,
            "MODULES_BYPASS": True,
            "SYSTEMD_THUNK_BYPASS": True,
            "REPO_BYPASS": True,
            "GIT_BYPASS": True,
            "GLOBAL_BINS_BYPASS": True,
            "SCCACHE_MISE_CONFIG_DIR": str(home / ".config/mise"),
        }
        deployments = {}
        for tool in ("sccache", "cargo-sweep"):
            deployment = home / ".local/opt" / f"{tool}-main"
            variables = common | {"DIR": str(deployment)}
            result = run("ansible-playbook", "-i", "localhost,", "-c", "local",
                         f"{tool}.opt.pb", "-e", json.dumps(variables), cwd=ROOT)
            (tmp / f"{tool}.render.log").write_text(result.stdout + result.stderr)
            deployments[tool] = deployment
        # Render must never reach the fake mise or apply its deferred links.
        assert not (tmp / "mise.log").exists()
        assert not (home / ".config/mise/conf.d/compfuzor-sccache.toml").exists()
        assert not (home / ".config/systemd/user").exists()
        assert main_config.read_text() == '[tools]\nrust = "nightly"\n'
        assert cargo_config.read_text() == '[build]\njobs = 2\n'
        yield tmp, home, deployments


def calls(tmp: Path) -> list[dict]:
    path = tmp / "mise.log"
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def fake_build(tmp: Path, deployment: Path, tool: str, home: Path) -> dict[str, str]:
    installed = tmp / f"installed {tool}"
    (installed / "bin").mkdir(parents=True, exist_ok=True)
    executable = installed / "bin" / tool
    executable.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$RUST_STORAGE_SWEEP_ARGS"\n')
    executable.chmod(0o755)
    env = os.environ | {
        "HOME": str(home), "RUST_STORAGE_INSTALLED": str(installed),
        "RUST_STORAGE_LOG": str(tmp / "mise.log"),
        "RUST_STORAGE_SWEEP_ARGS": str(tmp / "sweep.args"),
    }
    before = len(calls(tmp))
    run(str(deployment / "bin/build.sh"), cwd=ROOT, env=env)
    pin = "aqua:mozilla/sccache@0.18.0" if tool == "sccache" else "cargo:cargo-sweep@0.8.0"
    assert [call["argv"] for call in calls(tmp)[before:]] == [["install", pin], ["where", pin]]
    assert all(call["cwd"] == str(home) for call in calls(tmp)[before:])
    assert (deployment / "bin" / tool).is_symlink()
    assert (deployment / "bin" / tool).resolve() == executable
    return env


def test_render_user_units_mise_env_and_inert_lanes(rendered):
    tmp, home, deployments = rendered
    sccache = deployments["sccache"]
    sweep = deployments["cargo-sweep"]
    for deployment in deployments.values():
        assert (deployment / "bin/build.sh").exists()
        assert (deployment / "bin/install-user.sh").exists()
        assert (deployment / "bin/status.sh").exists()
        assert not (deployment / "bin/install-service.sh").exists()
        links = json.loads((deployment / "links.json").read_text())["links"]
        assert links and all(link["scope"] == "user" for link in links)
        assert not any(link["dest"].startswith("/etc/") for link in links)
        assert not (deployment / "bin" / deployment.name.removesuffix("-main")).exists()
    unit = (sccache / "etc/sccache-main.service").read_text()
    assert f'ExecStart="{sccache}/bin/sccache"\n' in unit
    assert "Type=exec" in unit and "WantedBy=default.target" in unit
    assert "--start-server" not in unit
    for setting in ("SCCACHE_START_SERVER=1", "SCCACHE_NO_DAEMON=1",
                    "SCCACHE_IDLE_TIMEOUT=0", "SCCACHE_CACHE_SIZE=20G"):
        assert setting in unit
    config = tomllib.loads((sccache / "etc/compfuzor-sccache.toml").read_text())
    assert config["env"] == {
        "RUSTC_WRAPPER": str(sccache / "bin/sccache"),
        "SCCACHE_DIR": str(home / ".cache/sccache"), "SCCACHE_CACHE_SIZE": "20G",
    }
    assert f'SCCACHE_DIR={config["env"]["SCCACHE_DIR"]}' in unit
    for profile, calendar in (("src", "Mon,Thu *-*-* 03:00:00"), ("archive", "*-*-01 04:00:00")):
        timer = (sweep / f"etc/cargo-sweep-main-{profile}.timer").read_text()
        service = (sweep / f"etc/cargo-sweep-main-{profile}.service").read_text()
        assert f"OnCalendar={calendar}" in timer
        assert "Persistent=True" in timer
        assert "WantedBy=timers.target" in timer
        assert "WorkingDirectory=%h" in service
        assert f'ExecStart="{sweep}/bin/sweep.sh" {profile} --apply' in service
        assert "WantedBy=default.target" not in service
    assert len(list(sweep.joinpath("etc").glob("*.timer"))) == 2
    assert len(list(sweep.joinpath("etc").glob("*.service"))) == 2


def test_build_pinned_mise_and_direct_executables(rendered):
    tmp, home, deployments = rendered
    for tool, deployment in deployments.items():
        fake_build(tmp, deployment, tool, home)
    assert (home / ".cache/sccache").is_dir()


def test_sweep_default_preview_explicit_apply_missing_root_and_overlap(rendered):
    tmp, home, deployments = rendered
    deployment = deployments["cargo-sweep"]
    env = fake_build(tmp, deployment, "cargo-sweep", home)
    script = deployment / "bin/sweep.sh"
    for profile, days in (("src", "14"), ("archive", "30")):
        run(str(script), profile, cwd=ROOT, env=env)
        assert (tmp / "sweep.args").read_text().splitlines() == [
            "sweep", "--recursive", "--time", days, "--dry-run", "--verbose", "--", str(home / profile),
        ]
        invocation = calls(tmp)[-1]
        assert invocation["cwd"] == str(home)
        assert invocation["argv"][:3] == ["exec", "--", str(deployment / "bin/cargo-sweep")]
        assert invocation["env"] == {
            "MISE_AUTO_INSTALL": "false", "MISE_EXEC_AUTO_INSTALL": "false", "RUSTUP_AUTO_INSTALL": "0",
        }
        run(str(script), profile, "--apply", cwd=ROOT, env=env)
        assert (tmp / "sweep.args").read_text().splitlines() == [
            "sweep", "--recursive", "--time", days, "--", str(home / profile),
        ]
    before = len(calls(tmp))
    invalid = run(str(script), "src", "--bogus", cwd=ROOT, env=env, check=False)
    assert invalid.returncode == 2 and len(calls(tmp)) == before
    (home / "src").rmdir()
    missing = run(str(script), "src", "--apply", cwd=ROOT, env=env, check=False)
    assert missing.returncode != 0 and "root does not exist" in missing.stderr
    assert len(calls(tmp)) == before
    (home / "src").mkdir()
    lock = home / ".local/state/compfuzor/cargo-sweep.lock"
    with lock.open("w") as holder:
        fcntl.flock(holder, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for profile in ("src", "archive"):
            overlap = run(str(script), profile, "--apply", cwd=ROOT, env=env)
            assert "skipping" in overlap.stdout and len(calls(tmp)) == before
    # Invalid root is checked even when another sweep holds the lock.
    run(str(script), "src", cwd=ROOT, env=env)
    assert len(calls(tmp)) == before + 1


def test_dropin_link_preserves_main_config_and_real_mise_loads_it(rendered):
    tmp, home, deployments = rendered
    deployment = deployments["sccache"]
    source = deployment / "etc/compfuzor-sccache.toml"
    main = home / ".config/mise/config.toml"
    original = main.read_bytes()
    plan = json.loads((deployment / "links.json").read_text())["links"]
    record = next(link for link in plan if link["dest"].endswith("/conf.d/compfuzor-sccache.toml"))
    env = os.environ | {"HOME": str(home), "DIR": str(deployment), "ENV_BYPASS": "1"}
    applied = run(str(deployment / "bin/links.mjs"), "apply", "--scope", "user", "--id", record["id"], cwd=ROOT, env=env)
    destination = home / ".config/mise/conf.d/compfuzor-sccache.toml"
    assert destination.is_symlink() and destination.resolve() == source.resolve(), (record, applied.stdout, applied.stderr)
    assert main.read_bytes() == original
    assert (home / ".cargo/config.toml").read_text() == '[build]\njobs = 2\n'
    # Actual mise, isolated HOME/config/data/cache: read config env, never install.
    mise_env = env | {
        "MISE_CONFIG_DIR": str(home / ".config/mise"),
        "MISE_DATA_DIR": str(home / "mise-data"),
        "MISE_CACHE_DIR": str(home / "mise-cache"),
        "MISE_STATE_DIR": str(home / "mise-state"),
        "MISE_SYSTEM_CONFIG_DIR": str(home / "empty-system-config"),
        "MISE_CEILING_PATHS": str(home),
        "MISE_AUTO_INSTALL": "false", "MISE_EXEC_AUTO_INSTALL": "false",
        "MISE_CHECK_FOR_UPDATES": "false", "MISE_OFFLINE": "true",
        # This check is about env/trust loading, not nightly resolution.
        "MISE_DISABLE_TOOLS": "rust",
    }
    result = run("/usr/bin/mise", "env", "--json", cwd=home, env=mise_env)
    loaded = json.loads(result.stdout)
    assert loaded["RUSTC_WRAPPER"] == str(deployment / "bin/sccache")
    assert loaded["SCCACHE_DIR"] == str(home / ".cache/sccache")
    assert loaded["SCCACHE_CACHE_SIZE"] == "20G"
    assert "SCCACHE_START_SERVER" not in loaded and "SCCACHE_NO_DAEMON" not in loaded
    assert main.read_bytes() == original


def test_install_sweep_uses_user_manager_and_only_starts_timers(rendered):
    tmp, home, deployments = rendered
    deployment = deployments["cargo-sweep"]
    shim = tmp / "systemctl shim"
    shim.mkdir()
    systemctl = shim / "systemctl"
    systemctl.write_text(f'#!{sys.executable}\n' + '''
import json, os, sys
with open(os.environ["RUST_STORAGE_SYSTEMCTL_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
''')
    systemctl.chmod(0o755)
    env = os.environ | {
        "HOME": str(home), "DIR": str(deployment), "ENV_BYPASS": "1",
        "PATH": f"{shim}:/usr/local/bin:/usr/bin:/bin",
        "RUST_STORAGE_SYSTEMCTL_LOG": str(tmp / "systemctl.log"),
    }
    run(str(deployment / "bin/install-user.sh"), cwd=ROOT, env=env)
    invocations = [json.loads(line) for line in (tmp / "systemctl.log").read_text().splitlines()]
    assert invocations and all(args[0] == "--user" for args in invocations)
    enabled = [args for args in invocations if "enable" in args]
    assert len(enabled) == 2
    assert {args[-1] for args in enabled} == {"cargo-sweep-main-src.timer", "cargo-sweep-main-archive.timer"}
    assert all("--now" in args for args in enabled)
    for profile in ("src", "archive"):
        for suffix in ("service", "timer"):
            unit = home / f".config/systemd/user/cargo-sweep-main-{profile}.{suffix}"
            assert unit.is_symlink()
