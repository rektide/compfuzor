#!/usr/bin/env python3
"""Render opt-in native proxy discovery only into isolated fixture roots."""
from __future__ import annotations

import argparse
from pathlib import Path
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "files/opencode/opencode-client-env.zsh"
HARNESS = runpy.run_path(str(ROOT / "tests/integration/proxy_env_adoption.test.py"))


def render(root: Path, playbook: str, extra: dict | None = None) -> str:
    root.mkdir(parents=True, exist_ok=True)
    environment = HARNESS["isolated_environment"](root)
    deployment = root / "deployment"
    settings = {
        # The existing generic file writer treats empty content as a template
        # lookup. Keep this fixture focused on discovery, as the ENV adoption
        # suite does, rather than exercising that separate empty-priority bug.
        "ENV_PRIO": {"KEEP": "seed"},
        "OPENCODE_PRIMARY_PASSWORDS_DIR": str(root / "config" / "secrets"),
        "OPENCODE_DISCOVERY_FILE": str(root / "state" / "service-local.json"),
        **(extra or {}),
    }
    HARNESS["render"](root, deployment, ROOT / playbook, environment, settings)
    if "bus-proxy" in playbook:
        HARNESS["assemble"](deployment, environment)
    assert not (root / "state" / "service-local.json").exists(), "playbook must not publish runtime state"
    output = deployment / "etc/env-projections/proxy-service.env" if "bus-proxy" in playbook else deployment / "env"
    return output.read_text(encoding="utf-8")


def test_rendering() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-proxy-discovery-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        default = render(root / "off", "opencode-bus-proxy.src.pb")
        assert 'BUS_PROXY_UPSTREAM="http://127.0.0.1:49373"' in default
        assert 'BUS_PROXY_LISTEN="127.0.0.1:49372"' in default
        assert 'BUS_PROXY_CREDENTIAL="OPENCODE_PASSWORD"' in default
        assert "BUS_PROXY_PASSWORD_FILE=" not in default
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
            "OPENCODE_PRIMARY_PORT": 49473, "OPENCODE_BUS_PROXY_PORT": 49472,
        })
        assert 'BUS_PROXY_UPSTREAM="http://127.0.0.1:49473"' in stomp
        assert 'BUS_PROXY_LISTEN="127.0.0.1:49472"' in stomp
        assert 'BUS_PROXY_SERVICE_MODE="stomp"' in stomp
        assert 'BUS_PROXY_SERVICE_METADATA="false"' in stomp
        assert "BUS_PROXY_SERVICE_WATCH_HELPER=" not in stomp
        assert_proxy_shell(root / "stomp", "http://127.0.0.1:49472")


def test_origin_rendering() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-origin-discovery-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        origin = render(root / "origin", "opencode.src.pb", {"OPENCODE_BUS_PROXY_DISCOVERY": True})
        assert 'OPENCODE_PROXY_URL="http://127.0.0.1:49372"' in origin
        assert 'OPENCODE_SERVICE_METADATA="true"' in origin
        zim_env = root / "origin" / "deployment" / "etc" / "zim-modules"
        assert (zim_env / "opencode-client-args" / "init.zsh").is_file()
        assert not any("OPENCODE_PROXY_URL=" in item.read_text() for item in zim_env.rglob("*.zsh"))


def assert_proxy_shell(root: Path, url: str) -> None:
    etc = root / "deployment" / "etc"
    module = etc / "zim-modules" / "opencode-bus-proxy-client-env" / "init.zsh"
    fragment = etc / "zim" / "zimrc" / "active" / "56-opencode-bus-proxy-client-env.conf"
    assert str(module.parent) in fragment.read_text()
    body = '''
      unset OPENCODE_PROXY_URL OPENCODE_ARGS
      source "$1" || exit $?
      [[ $OPENCODE_PROXY_URL == $2 && ${+OPENCODE_ARGS} == 0 ]] || exit 10
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy-only", action="store_true", help="omit the independent origin render")
    args = parser.parse_args()
    test_client_module_does_not_route_or_erase_user_functions()
    test_rendering()
    if not args.proxy_only:
        test_origin_rendering()
    print("ok: native discovery configuration and Zim endpoint metadata; no synthesized routing or activation")
