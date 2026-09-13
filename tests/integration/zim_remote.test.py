#!/usr/bin/env python3
"""Exercise explicit Zim producer promotion to canonical donor tooling."""

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
        main_target = host / "etc" / "zimrc.d"
        env_target = host / "etc" / "zimenv.d"
        (host / "bin").mkdir(parents=True)
        (host / "etc").mkdir()
        (producer / "etc" / "zim" / "zimrc" / "active").mkdir(parents=True)
        (producer / "etc" / "zim" / "zimenv" / "disabled").mkdir(parents=True)
        enabled = producer / "etc" / "zim" / "zimrc" / "active" / "20-enabled.conf"
        disabled_source = producer / "etc" / "zim" / "zimenv" / "disabled" / "40-disabled.conf"
        enabled.write_text("zmodule enabled\n")
        disabled_source.write_text("zmodule disabled\n")

        manager = host / "bin" / "config-remote.mjs"
        manager.write_text((ROOT / "build" / "runtime" / "compfuzor-runtime.mjs").read_text())
        manager.chmod(0o770)
        installer = host / "bin" / "install-zim-donor.sh"
        installer.write_text((ROOT / "files" / "install-zim-donor.sh").read_text().replace("{{DIR}}", str(host)))
        installer.chmod(0o770)
        (host / "etc" / "config.spec.json").write_text(json.dumps({"remotes": {
            "zimrc": {
                "config": "zimrc", "directory": str(main_target), "pattern": "*.conf", "disabled_suffix": ".disabled"
            },
            "zimenv": {
                "config": "zimenv", "directory": str(env_target), "pattern": "*.conf", "disabled_suffix": ".disabled"
            }
        }}))
        log = root / "rebuild.log"
        rebuild = host / "bin" / "config" / "command.mjs"
        rebuild.parent.mkdir()
        rebuild.write_text(f'#!/bin/sh\necho "$@" >> "{log}"\n')
        rebuild.chmod(0o770)
        build_log = root / "build.log"
        channel_builder = host / "bin" / "zimfw-channel.sh"
        channel_builder.write_text(f'#!/bin/sh\necho "$@" >> "{build_log}"\n')
        channel_builder.chmod(0o770)

        result = subprocess.run([str(installer), str(producer)], text=True, capture_output=True, check=False)
        assert result.returncode == 0, result.stderr
        active = main_target / enabled.name
        disabled = env_target / f"{disabled_source.name}.disabled"
        assert active.is_symlink() and active.resolve() == enabled
        assert disabled.is_symlink() and disabled.resolve() == disabled_source
        assert log.read_text().splitlines() == [
            "--action assemble --context canonical zimenv",
            "--action assemble --context canonical zimenv",
            "--action assemble --context canonical zimrc",
        ]
        assert not build_log.exists()


if __name__ == "__main__":
    test_zim_remote()
    print("ok: Zim canonical donor promotion")
