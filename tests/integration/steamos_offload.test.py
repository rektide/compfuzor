#!/usr/bin/env python3
"""Render the SteamOS offload bootstrap: plain bind mounts, no seed layer."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], env: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)


def test_steamos_offload() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-steamos-offload-") as temporary:
        scratch = Path(temporary)
        srvs = scratch / "srv"
        offload = scratch / "offload"
        srvs.mkdir()
        offload.mkdir()
        extra = {
            "SRVS_DIR": str(srvs),
            "STEAMOS_OFFLOAD_ROOT": str(offload),
            "ENV_BYPASS": True,
            "PKGS_BYPASS": True,
            "APT_BYPASS": True,
            "APTLANE_BYPASS": True,
            "MODULES_BYPASS": True,
            "REPO_BYPASS": True,
            "SYSTEMD_THUNK_BYPASS": True,
            "BINS_RUN_BYPASS": True,
            "GLOBAL_BINS_BYPASS": True,
            "DIR_LINK_BYPASS": True,
            "COMFUZOR_SHOULD_BECOME": False,
        }
        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        rendered = run(
            [
                "ansible-playbook",
                "-i",
                "localhost,",
                "-c",
                "local",
                "steamos-offload.srv.pb",
                "-e",
                json.dumps(extra),
            ],
            env,
        )
        if rendered.returncode:
            raise AssertionError(f"render failed:\n{rendered.stdout}\n{rendered.stderr}")

        deployment = srvs / "steamos-offload-main"
        etc = deployment / "etc"
        usr_mount = etc / "usr-local.mount"
        etc_mount = etc / "etc-opt.mount"
        for unit, where, source in (
            (usr_mount, "/usr/local", offload / "usr/local"),
            (etc_mount, "/etc/opt", offload / "etc/opt"),
        ):
            text = unit.read_text(encoding="utf-8")
            for fragment in (
                f"What={source}",
                f"Where={where}",
                "Type=none",
                "Options=bind",
                f"ConditionPathExists={source}",
                "WantedBy=holo-offload.target",
            ):
                if fragment not in text:
                    raise AssertionError(f"{unit.name}: missing {fragment!r}:\n{text}")
        if (etc / "steamos-offload-seed.service").exists():
            raise AssertionError("seed service rendered")
        seed = deployment / "bin/seed.sh"
        seed_text = seed.read_text(encoding="utf-8")
        for fragment in (
            "usr/local",
            "etc/opt",
            "rsync -aHAXx",
            "--backup",
            "mountpoint -q",
        ):
            if fragment not in seed_text:
                raise AssertionError(f"seed.sh missing {fragment!r}:\n{seed_text}")
        if not (offload / "usr/local").is_dir() or not (offload / "etc/opt").is_dir():
            raise AssertionError("backing directories not created")

        verified = run(["systemd-analyze", "verify", str(usr_mount), str(etc_mount)], env)
        if verified.returncode:
            raise AssertionError(f"unit verification failed:\n{verified.stdout}\n{verified.stderr}")

        aggregate = (deployment / "bin/install-systemd.sh").read_text(encoding="utf-8")
        ordered = ["install-mount-usr-local.sh", "install-mount-etc-opt.sh"]
        positions = [aggregate.find(name) for name in ordered]
        if any(position < 0 for position in positions) or positions != sorted(positions):
            raise AssertionError(f"unexpected installer order: {positions}\n{aggregate}")
        for name in ordered:
            leaf = deployment / f"bin/{name}"
            if "UNIT_LINK_DEFAULT=copy" not in leaf.read_text(encoding="utf-8"):
                raise AssertionError(f"copy strategy missing from {leaf}")
        if list((deployment / "bin").glob("install-service-*")):
            raise AssertionError("unexpected service installer rendered")

    print("ok: SteamOS offload renders plain bind mounts with durable backing")


if __name__ == "__main__":
    test_steamos_offload()
