#!/usr/bin/env python3
"""Opt-in live-account smoke test. Run AS the prepared account, from its HOME.

No installs, service starts, config writes, or model requests. --http additionally
checks the existing proxy and origin using the account's provisioned credential.
See doc/config/zimtest-rehearsal.md for preparation and known deployment gaps.
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


def shell_probe(home: Path, env: dict[str, str], interactive: bool, origin: str, proxy: str | None) -> None:
    probe = r'''
      [[ $MISE_CONFIG_DIR == $HOME/.config/mise2/config ]] || exit 21
      [[ $(mise settings get npm.package_manager) == pnpm ]] || exit 22
      if [[ -o interactive ]]; then
        (( ${+functions[_mise_hook]} )) || exit 23
        [[ $OPENCODE_SERVER_URL == $1 ]] || exit 24
        [[ $OPENCODE_SERVER_PORT == ${1##*:} ]] || exit 24
        [[ -r $OPENCODE_PASSWORD_FILE && -n $OPENCODE_PASSWORD ]] || exit 25
        [[ $OPENCODE_PASSWORD == "$(<$OPENCODE_PASSWORD_FILE)" ]] || exit 26
        (( ! ${+functions[opencode]} )) || exit 27
        [[ -s $HOME/.cache/zim2/modules/zim-opencode/functions/_opencode ]] || exit 28
        if [[ -n $2 ]]; then
          opencode api --server "$2" get /api/info >/dev/null || exit 31
        fi
      else
        [[ :$PATH: == *:$HOME/.local/share/mise/shims:* ]] || exit 29
        [[ -z ${OPENCODE_PASSWORD:-} ]] || exit 30
      fi
      print -r -- 'account-shell-ok'
    '''
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ["zsh", "-lic" if interactive else "-lc", probe, "account-probe", origin, proxy or ""],
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
    parser.add_argument("--origin-url", default="http://127.0.0.1:49373")
    parser.add_argument("--proxy-url", default="http://127.0.0.1:49372")
    args = parser.parse_args()
    account = pwd.getpwuid(os.getuid())
    home = Path(account.pw_dir)
    assert os.getuid() != 0, "run as the test account, not root"
    env = {
        "HOME": str(home), "USER": account.pw_name, "LOGNAME": account.pw_name,
        "PATH": "/usr/local/bin:/usr/bin:/bin", "TERM": "xterm-256color",
    }
    for interactive in (False, True):
        shell_probe(home, env, interactive, args.origin_url, args.proxy_url if args.http else None)
    for deployment, command in (("zim2-main", "status-zim.sh"), ("mise2-main", "status.sh")):
        result = subprocess.run(
            [str(home / ".local/opt" / deployment / "bin" / command)],
            cwd=home, env=env, capture_output=True, timeout=60,
        )
        assert result.returncode == 0, f"{deployment}/{command} failed: inspect its output locally"
        print(f"ok: {deployment}/{command}")
    if args.http:
        password = (home / ".config/opencode/secrets/OPENCODE_PASSWORD").read_text().strip()
        auth = base64.b64encode(f"opencode:{password}".encode()).decode()
        def get(url: str) -> dict:
            request = urllib.request.Request(url, headers={"Authorization": f"Basic {auth}"})
            with urllib.request.urlopen(request, timeout=10) as response:
                assert response.status == 200
                return json.load(response)
        origin = get(args.origin_url + "/api/info")
        proxy = get(args.proxy_url + "/api/info")
        assert origin == proxy, "proxy and origin identities differ"
        health = get(args.proxy_url + "/_bus/health")
        assert health.get("ready") is True, "proxy source not ready"
        print(f"ok: authenticated forwarding {args.proxy_url} -> {args.origin_url}; source ready")


if __name__ == "__main__":
    main()
