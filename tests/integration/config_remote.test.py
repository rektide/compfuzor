#!/usr/bin/env python3
"""Exercise remote config symlink lifecycle and transactional rebuilds."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed: {command}\n{result.stdout}\n{result.stderr}")
    return result


def test_config_remote() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-config-remote-") as tmp:
        root = Path(tmp)
        host = root / "host"
        target = host / "etc" / "fragments"
        sources = root / "producer" / "etc"
        (host / "bin").mkdir(parents=True)
        sources.mkdir(parents=True)
        manager = host / "bin" / "config-remote.ts"
        manager.write_text(
            (ROOT / "files" / "config-remote.ts").read_text().replace("{{DIR}}", str(host)), encoding="utf-8"
        )
        manager.chmod(0o770)
        (host / "etc").mkdir(exist_ok=True)
        (host / "etc" / "config.spec.json").write_text(json.dumps({"remotes": {"servers": {
            "config": "app", "directory": str(target), "pattern": "*.json", "disabled_suffix": ".disabled"
        }}}), encoding="utf-8")
        rebuild_log = root / "rebuild.log"
        rebuild = host / "bin" / "config.sh"
        rebuild.write_text(f'#!/bin/sh\necho "$@" >> "{rebuild_log}"\nexit "${{REBUILD_FAIL:-0}}"\n', encoding="utf-8")
        rebuild.chmod(0o770)

        one = sources / "one.json"
        two = sources / "two.json"
        one.write_text('{"version": 1}\n')
        two.write_text('{"version": 2}\n')
        listing = run([str(manager), "list"])
        assert "servers\tconfig=app" in listing.stdout and str(target / "*.json") in listing.stdout
        run([str(manager), "link", "servers", str(one), "example.json"])
        active = target / "example.json"
        assert active.is_symlink() and active.resolve() == one
        assert rebuild_log.read_text().splitlines() == ["app"]

        source_before = two.read_text()
        run([str(manager), "put", "servers", str(two), "example.json"])
        assert active.resolve() == two
        assert two.read_text() == source_before
        run([str(manager), "disable", "servers", "example.json"])
        disabled = target / "example.json.disabled"
        assert disabled.is_symlink() and not os.path.lexists(active)
        run([str(manager), "put", "servers", str(one), "example.json"])
        assert disabled.resolve() == one and not os.path.lexists(active)
        status = run([str(manager), "status", "servers", "example.json"])
        assert "disabled" in status.stdout and str(one.resolve()) in status.stdout
        run([str(manager), "enable", "servers", "example.json"])
        assert active.is_symlink() and not os.path.lexists(disabled)

        rejected = run([str(manager), "put", "servers", str(one), "bad.conf"], check=False)
        assert rejected.returncode == 1 and "does not match" in rejected.stderr
        regular = target / "regular.json"
        regular.write_text("local\n")
        overwrite = run([str(manager), "put", "servers", str(one), "regular.json"], check=False)
        remove_regular = run([str(manager), "remove", "servers", "regular.json"], check=False)
        assert overwrite.returncode == 1 and remove_regular.returncode == 1 and regular.read_text() == "local\n"
        disabled.symlink_to(two)
        conflict = run([str(manager), "remove", "servers", "example.json"], check=False)
        assert conflict.returncode == 1 and "both active and disabled" in conflict.stderr
        disabled.unlink()

        env = os.environ.copy()
        env["REBUILD_FAIL"] = "1"
        failed = subprocess.run([str(manager), "put", "servers", str(two), "example.json"], text=True, capture_output=True, env=env)
        assert failed.returncode == 1 and active.resolve() == one
        failed_remove = subprocess.run([str(manager), "remove", "servers", "example.json"], text=True, capture_output=True, env=env)
        assert failed_remove.returncode == 1 and active.resolve() == one
        failed_disable = subprocess.run(
            [str(manager), "disable", "servers", "example.json"], text=True, capture_output=True, env=env
        )
        assert failed_disable.returncode == 1 and active.is_symlink() and not os.path.lexists(disabled)

        run([str(manager), "remove", "servers", "example.json"])
        assert not os.path.lexists(active)
        run([str(manager), "put", "servers", str(one), "dangling.json"])
        one.unlink()
        dangling = run([str(manager), "status", "servers", "dangling.json"])
        assert "enabled" in dangling.stdout
        run([str(manager), "remove", "servers", "dangling.json"])


if __name__ == "__main__":
    test_config_remote()
    print("ok: remote config lifecycle")
