#!/usr/bin/env python3
"""Exercise Zim producer delegation to consumer-owned remote tooling."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def test_zim_remote() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-zim-remote-") as tmp:
        root = Path(tmp)
        host = root / "host"
        producer = root / "producer"
        target = host / "etc" / "zimfw.conf.d"
        (host / "bin").mkdir(parents=True)
        (host / "etc").mkdir()
        (producer / "etc" / "zim").mkdir(parents=True)
        (producer / "etc" / "zim-disabled").mkdir()
        enabled = producer / "etc" / "zim" / "20-enabled.conf"
        disabled_source = producer / "etc" / "zim-disabled" / "40-disabled.conf"
        enabled.write_text("zmodule enabled\n")
        disabled_source.write_text("zmodule disabled\n")

        manager = host / "bin" / "config-remote.ts"
        manager.write_text((ROOT / "files" / "config-remote.ts").read_text().replace("{{DIR}}", str(host)))
        manager.chmod(0o770)
        installer = host / "bin" / "install-zim.sh"
        installer.write_text((ROOT / "files" / "install-zim.sh").read_text().replace("{{DIR}}", str(host)))
        installer.chmod(0o770)
        (host / "etc" / "config.spec.json").write_text(json.dumps({"remotes": {"zimfw.conf.d": {
            "config": "zimfw", "directory": str(target), "pattern": "*.conf", "disabled_suffix": ".disabled"
        }}}))
        log = root / "rebuild.log"
        rebuild = host / "bin" / "config.sh"
        rebuild.write_text(f'#!/bin/sh\necho "$@" >> "{log}"\n')
        rebuild.chmod(0o770)

        result = subprocess.run([str(installer), str(producer)], text=True, capture_output=True, check=False)
        assert result.returncode == 0, result.stderr
        active = target / enabled.name
        disabled = target / f"{disabled_source.name}.disabled"
        assert active.is_symlink() and active.resolve() == enabled
        assert disabled.is_symlink() and disabled.resolve() == disabled_source
        assert log.read_text().splitlines() == ["zimfw", "zimfw", "zimfw"]


if __name__ == "__main__":
    test_zim_remote()
    print("ok: Zim remote delegation")
