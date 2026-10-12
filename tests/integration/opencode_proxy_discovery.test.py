#!/usr/bin/env python3
"""Render opt-in native proxy discovery only into isolated fixture roots."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "files/opencode/opencode-client-env.zsh"


def render(root: Path, playbook: str, extra: dict | None = None) -> str:
    for directory in ("src", "opts", "etc-opt", "bins", "units", "config"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    settings = {
        "SRCS_DIR": str(root / "src"), "OPTS_DIR": str(root / "opts"),
        "ETCS_DIR": str(root / "etc-opt"), "GLOBAL_BINS_DIR": str(root / "bins"),
        "SYSTEMD_USER_UNIT_DIR": str(root / "units"),
        "SYSTEMD_SYSTEM_UNIT_DIR": str(root / "units"),
        "PASSWORDS_DIR": str(root / "config" / "secrets"),
        "OPENCODE_DISCOVERY_FILE": str(root / "state" / "service-local.json"),
        "PKGS_BYPASS": True, "APT_BYPASS": True, "MODULES_BYPASS": True,
        "REPO_BYPASS": True, "GIT_BYPASS": True, "LINKS_BYPASS": True,
        "GLOBAL_BINS_BYPASS": True, "BINS_RUN_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True,
        **(extra or {}),
    }
    variables = root / "variables.json"
    variables.write_text(json.dumps(settings), encoding="utf-8")
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", playbook, "-e", f"@{variables}"],
        cwd=ROOT, env={**os.environ, "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
        text=True, capture_output=True, check=False, timeout=120,
    )
    if result.returncode:
        raise AssertionError(f"fixture render failed:\n{result.stdout}\n{result.stderr}")
    name = "opencode-bus-proxy-git" if "bus-proxy" in playbook else "opencode-git"
    assert not (root / "state" / "service-local.json").exists(), "playbook must not publish runtime state"
    return (root / "src" / name / "env").read_text(encoding="utf-8")


def test_rendering() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-proxy-discovery-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        default = render(root / "off", "opencode-bus-proxy.src.pb")
        assert 'BUS_PROXY_UPSTREAM="http://127.0.0.1:49373"' in default
        assert 'BUS_PROXY_LISTEN="127.0.0.1:49372"' in default
        assert "BUS_PROXY_SERVICE_FILE=" not in default
        assert_proxy_shell(root / "off", "http://127.0.0.1:49372")
        cooperative = render(root / "coop", "opencode-bus-proxy.src.pb", {"OPENCODE_BUS_PROXY_DISCOVERY": True})
        assert f'BUS_PROXY_SERVICE_FILE="{root}/coop/state/service-local.json"' in cooperative
        assert 'BUS_PROXY_SERVICE_MODE="cooperate"' in cooperative
        assert 'BUS_PROXY_SERVICE_METADATA="true"' in cooperative
        assert "BUS_PROXY_SERVICE_WATCH_HELPER=" in cooperative
        assert "BUS_PROXY_SERVICE_WATCH_SOURCE=" in cooperative
        stomp = render(root / "stomp", "opencode-bus-proxy.src.pb", {
            "OPENCODE_BUS_PROXY_DISCOVERY": True, "OPENCODE_BUS_PROXY_SERVICE_MODE": "stomp",
            "OPENCODE_BUS_PROXY_EFFECT_WATCH": False, "OPENCODE_DISCOVERY_METADATA": False,
            "OPENCODE_PRIMARY_PORT": 53173, "OPENCODE_BUS_PROXY_PORT": 53172,
        })
        assert 'BUS_PROXY_UPSTREAM="http://127.0.0.1:53173"' in stomp
        assert 'BUS_PROXY_LISTEN="127.0.0.1:53172"' in stomp
        assert 'BUS_PROXY_SERVICE_MODE="stomp"' in stomp
        assert 'BUS_PROXY_SERVICE_METADATA="false"' in stomp
        assert "BUS_PROXY_SERVICE_WATCH_HELPER=" not in stomp
        assert_proxy_shell(root / "stomp", "http://127.0.0.1:53172")


def test_origin_rendering() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-origin-discovery-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        origin = render(root / "origin", "opencode.src.pb", {"OPENCODE_BUS_PROXY_DISCOVERY": True})
        assert 'OPENCODE_PROXY_URL="http://127.0.0.1:49372"' in origin
        assert 'OPENCODE_SERVICE_METADATA="true"' in origin
        zim_env = root / "origin" / "etc-opt" / "opencode-git" / "zim-modules"
        assert (zim_env / "opencode-client-args" / "init.zsh").is_file()
        assert not any("OPENCODE_PROXY_URL=" in item.read_text() for item in zim_env.rglob("*.zsh"))


def assert_proxy_shell(root: Path, url: str) -> None:
    etc = root / "etc-opt" / "opencode-bus-proxy-git"
    module = etc / "zim-modules" / "opencode-bus-proxy-client-env" / "init.zsh"
    fragment = etc / "zim" / "zimrc" / "active" / "56-opencode-bus-proxy-client-env.conf"
    assert str(module.parent) in fragment.read_text()
    body = '''
      unset OPENCODE_PROXY_URL OPENCODE_ARGS
      source "$1"
      [[ $OPENCODE_PROXY_URL == $2 && $OPENCODE_ARGS == "--server $2" ]] || exit 10
      (( ! ${+functions[opencode]} )) || exit 11
      export OPENCODE_ARGS='--server http://explicit:1234'
      source "$1"
      [[ $OPENCODE_ARGS == '--server http://explicit:1234' ]] || exit 12
    '''
    result = subprocess.run(["zsh", "-dfc", body, "probe", str(module), url], text=True, capture_output=True)
    assert result.returncode == 0, result.stderr


def test_client_module_does_not_route_or_erase_user_functions() -> None:
    body = f"""
      export OPENCODE_PROXY_URL=http://127.0.0.1:49372
      opencode() {{ command opencode --server "$OPENCODE_PROXY_URL" "$@"; }}
      source {MODULE}
      (( ${{+functions[opencode]}} == 0 )) || exit 10
      opencode() {{ print user-function; }}
      source {MODULE}
      [[ "$(opencode)" == user-function ]] || exit 11
    """
    result = subprocess.run(["zsh", "-c", body], text=True, capture_output=True)
    assert result.returncode == 0, result.stderr


if __name__ == "__main__":
    test_client_module_does_not_route_or_erase_user_functions()
    test_rendering()
    test_origin_rendering()
    print("ok: native discovery configuration and explicit Zim proxy defaults; no shell wrapper or activation")
