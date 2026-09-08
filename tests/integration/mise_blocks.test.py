#!/usr/bin/env python3
"""Exercise Mise's independent Bash block installer and shared block status."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "config-contexts"
NODE = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def test_mise_bash_blocks() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mise block status-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "mise deployment with spaces"
        scenario = temporary / "scenario.json"
        block_in_file = temporary / "block-in-file"
        block_in_file.write_text(
            f'#!/bin/sh\nexec {NODE!r} {str(Path.home() / "src/block-in-file/dist/block-in-file.mjs")!r} "$@"\n',
            encoding="utf-8",
        )
        block_in_file.chmod(0o755)
        scenario.write_text(json.dumps({
            "TYPE": "mise",
            "NAME": "mise-main",
            "INSTANCE": "main",
            "DIR": str(payload),
            "ETC": str(payload / "etc"),
            "BINS_DIR": str(payload / "bin"),
            "GET_URLS": [],
            "PKGS": [],
            "ARCH_PKGS": [],
            "BINS_RUN_BYPASS": True,
            "PKGS_BYPASS": True,
            "APT_BYPASS": True,
            "REPO_BYPASS": True,
        }), encoding="utf-8")
        ansible_env = os.environ.copy()
        ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(ROOT / "mise.opt.pb"), "-e", f"@{scenario}"],
            cwd=ROOT,
            env=ansible_env,
        )

        assert not (payload / "etc" / "config.spec.json").exists()
        assert not (payload / "bin" / "config-user.sh").exists()
        assert (payload / "bin" / "status-mise-bash.sh").is_file()

        home = temporary / "home"
        bashrc = home / "startup" / ".bashrc"
        profile = home / "startup" / ".bash_profile"
        bashrc.parent.mkdir(parents=True)
        bashrc.write_text("unmanaged bashrc\n", encoding="utf-8")
        profile.write_text("unmanaged profile\n", encoding="utf-8")
        shim = temporary / "shim"
        shim.mkdir()
        mise_log = temporary / "mise.log"
        (shim / "mise").write_text(f'#!/bin/sh\necho called >> {str(mise_log)!r}\nexit 99\n', encoding="utf-8")
        (shim / "mise").chmod(0o755)
        env = os.environ.copy()
        env.update({
            "HOME": str(home),
            "BASH_RC": str(bashrc),
            "BASH_PROFILE": str(profile),
            "CONFIG_BLOCK_IN_FILE": str(block_in_file),
            "DIR": str(payload),
            "ENV_BYPASS": "1",
            "NAME": "mise-main",
            "PATH": os.pathsep.join((str(shim), str(Path(NODE).parent), str(temporary), "/usr/bin", "/bin")),
        })

        run([str(payload / "bin" / "install-bash-user.sh")], cwd=temporary, env=env)
        assert not mise_log.exists()
        assert "unmanaged bashrc" in bashrc.read_text(encoding="utf-8")
        assert "unmanaged profile" in profile.read_text(encoding="utf-8")
        for source, destination in (
            (payload / "etc" / "mise.bashrc", bashrc),
            (payload / "etc" / "mise.bash_profile", profile),
        ):
            projection = run(
                [str(block_in_file), "--read", "-n", "mise-main", str(destination)],
                cwd=temporary,
                env=env,
            )
            assert projection.stdout.encode() == source.read_bytes()

        clean = run([str(payload / "bin" / "status-mise-bash.sh")], cwd=temporary, env=env, check=False)
        assert clean.returncode == 0

        changed = temporary / "changed.bash"
        changed.write_text("echo changed\n", encoding="utf-8")
        run([str(block_in_file), "-n", "mise-main", "-i", str(changed), "-o", str(bashrc)], cwd=temporary, env=env)
        drift = run([str(payload / "bin" / "status-mise-bash.sh")], cwd=temporary, env=env, check=False)
        assert drift.returncode == 1 and "differs" in drift.stdout
        aggregate = run([str(payload / "bin" / "status.sh")], cwd=temporary, env=env, check=False)
        assert aggregate.returncode == 1 and "status-mise-bash.sh" in aggregate.stdout

        source = payload / "etc" / "mise.bash_profile"
        backup = source.read_bytes()
        source.unlink()
        missing = run([str(payload / "bin" / "status-mise-bash.sh")], cwd=temporary, env=env, check=False)
        assert missing.returncode == 1 and "block source is missing" in missing.stdout
        source.write_bytes(backup)


if __name__ == "__main__":
    test_mise_bash_blocks()
    print("ok: Mise Bash block status")
