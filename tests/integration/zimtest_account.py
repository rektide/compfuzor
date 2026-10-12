#!/usr/bin/env python3
"""Opt-in live-account smoke test. Run AS the prepared account, from its HOME.

No installs, service starts, config writes, or model requests. --http additionally
checks the existing proxy and origin using the account's provisioned credential.
See doc/config/zimtest-native-stack.md for preparation and known deployment gaps.
"""

from __future__ import annotations

import argparse
import base64
import errno
import json
import os
from pathlib import Path
import pty
import pwd
import select
import subprocess
import time
import urllib.request


def shell_probe(home: Path, env: dict[str, str], interactive: bool, origin: str, proxy: str, http: bool) -> None:
    probe = r'''
      [[ $MISE_CONFIG_DIR == $HOME/.config/mise2/config ]] || exit 21
      [[ $(mise settings get npm.package_manager) == pnpm ]] || exit 22
      [[ $(command -v opencode) == $HOME/.local/bin/opencode ]] || exit 33
      if [[ -o interactive ]]; then
        (( ${+functions[_mise_hook]} )) || exit 23
        _mise_hook
        [[ $(command -v opencode) == $HOME/.local/bin/opencode ]] || exit 33
        [[ $OPENCODE_SERVER_URL == $1 ]] || exit 24
        [[ $OPENCODE_SERVER_PORT == ${1##*:} ]] || exit 24
        [[ $OPENCODE_PROXY_URL == $2 && -z ${OPENCODE_ARGS:-} ]] || exit 32
        [[ -r $OPENCODE_PASSWORD_FILE && -n $OPENCODE_PASSWORD ]] || exit 25
        [[ $OPENCODE_PASSWORD == "$(<$OPENCODE_PASSWORD_FILE)" ]] || exit 26
        (( ! ${+functions[opencode]} )) || exit 27
        [[ -s $HOME/.cache/zim2/modules/zim-opencode/functions/_opencode ]] || exit 28
      else
        [[ :$PATH: == *:$HOME/.local/share/mise/shims:* ]] || exit 29
        [[ -z ${OPENCODE_PASSWORD:-} ]] || exit 30
      fi
      if [[ $3 == http ]]; then
        # Native discovery must work in BOTH modes, including the shell which
        # never imports any interactive credential/endpoint contribution.
        [[ -z ${OPENCODE_ARGS:-} ]] || exit 32
        [[ $(opencode api get /_bus/health) == '{"ready":true}' ]] || exit 31
      fi
      print -r -- 'account-shell-ok'
    '''
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ["zsh", "-lic" if interactive else "-lc", probe, "account-probe", origin, proxy, "http" if http else ""],
        cwd=home, env=env, stdin=slave, stdout=slave, stderr=slave,
    )
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + 60
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("shell probe exceeded 60 seconds")
            if not select.select([master], [], [], remaining)[0]:
                raise TimeoutError("shell probe exceeded 60 seconds")
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            output.extend(data)
        code = process.wait(timeout=5)
    finally:
        os.close(master)
        if process.poll() is None:
            process.kill()
            process.wait()
    text = output.decode(errors="replace")
    # Never include shell output in failures: extensions could print secrets.
    assert code == 0, f"{'interactive' if interactive else 'noninteractive'} shell assertion {code}"
    assert "account-shell-ok" in text, "shell did not reach the success marker"
    assert not any(error in text.lower() for error in ("permission denied", "no such file", "command not found", "error:", "failed", "changed since")), "shell startup reported an error (inspect locally)"
    print(f"ok: {'interactive' if interactive else 'noninteractive'} login shell")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--http", action="store_true")
    parser.add_argument("--origin-url", default="http://127.0.0.1:49473")
    parser.add_argument("--proxy-url", default="http://127.0.0.1:49472")
    parser.add_argument("--services", action="store_true", help="verify this account's live systemd credential copies")
    args = parser.parse_args()
    account = pwd.getpwuid(os.getuid())
    home = Path(account.pw_dir)
    assert os.getuid() != 0, "run as the test account, not root"
    env = {
        "HOME": str(home), "USER": account.pw_name, "LOGNAME": account.pw_name,
        "PATH": "/usr/local/bin:/usr/bin:/bin", "TERM": "xterm-256color",
    }
    for interactive in (False, True):
        shell_probe(home, env, interactive, args.origin_url, args.proxy_url, args.http)
    for deployment, command in (("zim2-main", "status-zim.sh"), ("mise2-main", "status.sh")):
        result = subprocess.run(
            [str(home / ".local/opt" / deployment / "bin" / command)],
            cwd=home, env=env, capture_output=True, timeout=60,
        )
        assert result.returncode == 0, f"{deployment}/{command} failed: inspect its output locally"
        print(f"ok: {deployment}/{command}")
    if args.http:
        password = (home / ".config/opencode/secrets/OPENCODE_PASSWORD").read_text().strip()
        record_path = home / ".local/state/opencode/service-local.json"
        record = json.loads(record_path.read_text())
        assert record_path.stat().st_mode & 0o777 == 0o600
        assert record["mode"] == "server" and record["url"] == args.proxy_url
        assert record["password"] == password
        config = home / ".config/opencode/service-local.json"
        assert not config.exists() or json.loads(config.read_text()).get("disabled") is not True
        auth = base64.b64encode(f"opencode:{password}".encode()).decode()
        def get(url: str) -> dict:
            request = urllib.request.Request(url, headers={"Authorization": f"Basic {auth}"})
            with urllib.request.urlopen(request, timeout=10) as response:
                assert response.status == 200
                return json.load(response)
        origin = get(args.origin_url + "/api/info")
        proxy = get(args.proxy_url + "/api/info")
        assert origin == proxy, "proxy and origin identities differ"
        assert record["pid"] == origin["pid"] and record["version"] == origin["version"]
        health = get(args.proxy_url + "/_bus/health")
        assert health.get("ready") is True, "proxy source not ready"
        print(f"ok: authenticated forwarding {args.proxy_url} -> {args.origin_url}; source ready")
    if args.services:
        source = home / ".config/opencode/secrets/OPENCODE_PASSWORD"
        assert source.stat().st_uid == os.getuid() and source.stat().st_mode & 0o777 == 0o600
        manager_env = env | {
            "XDG_RUNTIME_DIR": f"/run/user/{os.getuid()}",
            "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{os.getuid()}/bus",
        }
        for unit in ("opencode.service", "opencode-bus-proxy.service"):
            pid = int(subprocess.check_output(["systemctl", "--user", "show", unit, "-p", "MainPID", "--value"], env=manager_env))
            assert pid > 0, f"{unit} is not running"
            values = dict(entry.split(b"=", 1) for entry in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0") if b"=" in entry)
            directory = Path(os.fsdecode(values[b"CREDENTIALS_DIRECTORY"]))
            credential = directory / "OPENCODE_PASSWORD"
            assert credential.read_bytes() == source.read_bytes(), f"{unit} has stale credential copy"
            assert credential.stat().st_mode & 0o077 == 0, f"{unit} credential is not private"
            assert b"OPENCODE_PASSWORD" not in values and b"OPENCODE_SERVER_PASSWORD" not in values
            if unit == "opencode.service":
                assert os.fsdecode(values[b"OPENCODE_PASSWORD_FILE"]) == str(credential)
            else:
                assert values[b"BUS_PROXY_CREDENTIAL"] == b"OPENCODE_PASSWORD"
                assert b"BUS_PROXY_PASSWORD_FILE" not in values
            print(f"ok: {unit} uses this account's systemd credential copy")


if __name__ == "__main__":
    main()
