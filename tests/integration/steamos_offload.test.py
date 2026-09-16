#!/usr/bin/env python3
"""Render and exercise the SteamOS offload bootstrap without privileged paths."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, **kwargs)


def check_file(path: Path, expected: str) -> None:
    actual = path.read_text(encoding="utf-8").strip()
    if actual != expected:
        raise AssertionError(f"{path}: expected {expected!r}, got {actual!r}")


def test_steamos_offload() -> None:
    with tempfile.TemporaryDirectory(prefix="compfuzor-steamos-offload-") as temporary:
        scratch = Path(temporary)
        opt = scratch / "opt"
        opt.mkdir()
        extra = {
            "OPTS_DIR": str(opt),
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
            env=env,
        )
        if rendered.returncode:
            raise AssertionError(f"render failed:\n{rendered.stdout}\n{rendered.stderr}")

        deployment = opt / "steamos-offload-main"
        etc = deployment / "etc"
        seed_unit = etc / "steamos-offload-seed.service"
        usr_mount = etc / "usr-local.mount"
        etc_mount = etc / "etc-opt.mount"
        seed_text = seed_unit.read_text(encoding="utf-8")
        if "DefaultDependencies=false" not in seed_text:
            raise AssertionError(seed_text)
        if "WantedBy=holo-offload.target" not in seed_text:
            raise AssertionError(seed_text)
        if "Where=/usr/local" not in usr_mount.read_text(encoding="utf-8"):
            raise AssertionError(usr_mount.read_text(encoding="utf-8"))
        if "Where=/etc/opt" not in etc_mount.read_text(encoding="utf-8"):
            raise AssertionError(etc_mount.read_text(encoding="utf-8"))

        verified = run(
            ["systemd-analyze", "verify", str(seed_unit), str(usr_mount), str(etc_mount)]
        )
        if verified.returncode:
            raise AssertionError(f"unit verification failed:\n{verified.stdout}\n{verified.stderr}")

        aggregate = (deployment / "bin/install-systemd.sh").read_text(encoding="utf-8")
        ordered = [
            "install-service-steamos-offload-seed.sh",
            "install-mount-usr-local.sh",
            "install-mount-etc-opt.sh",
        ]
        positions = [aggregate.find(name) for name in ordered]
        if any(position < 0 for position in positions) or positions != sorted(positions):
            raise AssertionError(f"unexpected installer order: {positions}\n{aggregate}")
        for name in ordered:
            leaf = deployment / f"bin/{name}"
            if "UNIT_LINK_DEFAULT=copy" not in leaf.read_text(encoding="utf-8"):
                raise AssertionError(f"copy strategy missing from {leaf}")

        source = scratch / "image"
        backing = scratch / "backing"
        (source / "usr/local").mkdir(parents=True)
        (source / "etc/opt").mkdir(parents=True)
        (backing / "usr/local").mkdir(parents=True)
        (backing / "etc/opt").mkdir(parents=True)
        (source / "usr/local/shared").write_text("image-v1\n", encoding="utf-8")
        (source / "etc/opt/config").write_text("etc-v1\n", encoding="utf-8")
        (backing / "usr/local/shared").write_text("old-local\n", encoding="utf-8")
        (backing / "usr/local/destination-only").write_text("keep-me\n", encoding="utf-8")

        script = deployment / "bin/seed-offloads.sh"
        seed_env = env | {
            "STEAMOS_OFFLOAD_ALLOW_NON_ROOT": "1",
            "STEAMOS_OFFLOAD_SOURCE_ROOT": str(source),
            "STEAMOS_OFFLOAD_ROOT": str(backing),
            "STEAMOS_BUILD_ID": "build-1",
        }
        first = run([str(script)], env=seed_env)
        if first.returncode:
            raise AssertionError(f"first seed failed:\n{first.stdout}\n{first.stderr}")
        check_file(backing / "usr/local/shared", "image-v1")
        check_file(backing / "usr/local/destination-only", "keep-me")
        archived = list((backing / ".compfuzor/archive/usr-local/build-1").rglob("shared"))
        if len(archived) != 1:
            raise AssertionError(f"expected one archived replacement, got {archived}")
        check_file(archived[0], "old-local")

        (backing / "usr/local/shared").write_text("local-after-seed\n", encoding="utf-8")
        second = run([str(script)], env=seed_env)
        if second.returncode:
            raise AssertionError(f"second seed failed:\n{second.stdout}\n{second.stderr}")
        check_file(backing / "usr/local/shared", "local-after-seed")

        (source / "usr/local/shared").write_text("image-v2\n", encoding="utf-8")
        third = run([str(script)], env=seed_env | {"STEAMOS_BUILD_ID": "build-2"})
        if third.returncode:
            raise AssertionError(f"new-build seed failed:\n{third.stdout}\n{third.stderr}")
        check_file(backing / "usr/local/shared", "image-v2")
        archived = list((backing / ".compfuzor/archive/usr-local/build-2").rglob("shared"))
        if len(archived) != 1:
            raise AssertionError(f"expected one new-build archive, got {archived}")
        check_file(archived[0], "local-after-seed")

    print("ok: SteamOS multi-unit offload bootstrap and seed/archive behavior")


if __name__ == "__main__":
    test_steamos_offload()
