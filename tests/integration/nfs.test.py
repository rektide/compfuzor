#!/usr/bin/env python3
"""Render the real NFS playbooks in scratch space; never install or mount.

Run: python3 tests/integration/nfs.test.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent/nfs"


def render(
    playbook: str, payload: Path, overrides: dict | None = None
) -> subprocess.CompletedProcess[str]:
    variables = {
        "DIR": str(payload),
        "ETC": str(payload / "etc"),
        "BINS_DIR": str(payload / "bin"),
        "PKGS_BYPASS": True,
        "APT_BYPASS": True,
        "MODULES_BYPASS": True,
        "BINS_RUN_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True,
        "GLOBAL_BINS_BYPASS": True,
        "USER": "",
        **(overrides or {}),
    }
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", playbook,
         "-e", json.dumps(variables)],
        cwd=ROOT,
        env={
            **os.environ,
            "ANSIBLE_NOCOLOR": "1",
            "ANSIBLE_CONFIG": str(ROOT / "ansible.cfg"),
            "HOME": str(payload.parent),
        },
        text=True,
        capture_output=True,
        check=False,
    )
    return result


def require_success(result: subprocess.CompletedProcess[str]) -> None:
    assert result.returncode == 0, result.stdout + result.stderr


def test_default_export(payload: Path) -> None:
    require_success(render("nfs-export.srv.pb", payload))
    fragments = list((payload / "etc").rglob("*.exports"))
    assert len(fragments) == 1, fragments
    fragment = fragments[0].read_text()
    assert '/srv/nfs-test' in fragment
    assert '127.0.0.1(rw,sync,no_subtree_check,root_squash)' in fragment
    assert "*(" not in fragment and "no_root_squash" not in fragment
    plan = json.loads((payload / "links.json").read_text())
    assert any(
        row["dest"] == "/etc/exports.d/nfs-export-test.exports"
        for row in plan["links"]
    )
    installer = (payload / "bin/install-nfs-export.sh").read_text()
    assert f"EXPORT_OWNER_DEFAULT={os.getuid()}" in installer
    assert f"EXPORT_GROUP_DEFAULT={os.getgid()}" in installer
    assert "nfs-server" in installer and "exportfs" in installer
    assert "exportfs -ra" not in installer and "exportfs -u" not in installer
    aggregate = (payload / "bin/install.sh").read_text()
    assert aggregate.index("install-apt.sh") < aggregate.index(
        "install-nfs-export.sh"
    )
    assert "install-links.sh" in aggregate
    # Link compositors normally run last. This installer must publish its
    # fragment itself before the distro service reads all exports on startup.
    assert installer.index("links.mjs") < installer.index("systemctl")


def test_default_mount(payload: Path) -> None:
    require_success(render("nfs.etc.pb", payload))
    mount = payload / r"etc/mnt-nfs\x2dtest.mount"
    automount = payload / r"etc/mnt-nfs\x2dtest.automount"
    text = mount.read_text()
    assert "What=127.0.0.1:/srv/nfs-test" in text
    assert "Where=/mnt/nfs-test" in text and "Type=nfs\n" in text
    assert "Options=vers=4.2,proto=tcp,hard,_netdev" in text
    assert "[Install]" not in text and "Alias=" not in text
    automatic = automount.read_text()
    assert "Where=/mnt/nfs-test" in automatic and "TimeoutIdleSec=15min" in automatic
    assert "Alias=" not in automatic
    assert "WantedBy=" in automatic
    scripts = list((payload / "bin").glob("install-mount*.sh"))
    assert scripts
    for script in scripts:
        if "automount" not in script.name:
            assert 'UNIT_ENABLE_TARGETS=""' in script.read_text()


def test_custom_mount(payload: Path) -> None:
    require_success(render("nfs.etc.pb", payload, {
        "INSTANCE": "media", "srv": "fileserver", "export_path": "/srv/media",
        "where": "/mnt/nfs-media", "mount_opts": "ro", "idle": "2min",
    }))
    mount = (payload / r"etc/mnt-nfs\x2dmedia.mount").read_text()
    assert "What=fileserver:/srv/media" in mount
    assert "Where=/mnt/nfs-media" in mount
    assert "Options=vers=4.2,proto=tcp,hard,_netdev,ro" in mount
    automatic = (payload / r"etc/mnt-nfs\x2dmedia.automount").read_text()
    assert "TimeoutIdleSec=2min" in automatic


def test_reject_usermode(payload: Path) -> None:
    for playbook in ("nfs-export.srv.pb", "nfs.etc.pb"):
        result = render(playbook, payload, {"USERMODE": True})
        assert result.returncode != 0, (
            f"{playbook} accepted user-scoped kernel NFS"
        )
        assert not (payload / "bin/install.sh").exists()
        assert not (payload / "bin/install-user.sh").exists()


def test_reject_root_paths(payload: Path) -> None:
    for playbook, overrides in (
        ("nfs-export.srv.pb", {"export_path": "/"}),
        ("nfs.etc.pb", {"where": "/"}),
    ):
        result = render(playbook, payload, overrides)
        assert result.returncode != 0, f"{playbook} accepted a root path"
        assert not (payload / "bin/install.sh").exists()


def test_reject_unsafe_declarations(payload: Path) -> None:
    for playbook, overrides in (
        ("nfs-export.srv.pb", {"export_path": "/srv/has space"}),
        ("nfs-export.srv.pb", {"export_path": "/srv/quote'path"}),
        ("nfs-export.srv.pb", {"export_path": "/srv/trailing\n"}),
        ("nfs-export.srv.pb", {"export_path": "/srv/../"}),
        ("nfs-export.srv.pb", {"clients": []}),
        ("nfs-export.srv.pb", {"clients": ["127.0.0.1\n"]}),
        ("nfs.etc.pb", {"where": "/mnt/has space"}),
        ("nfs.etc.pb", {"export_path": "/srv/trailing\n"}),
    ):
        result = render(playbook, payload, overrides)
        assert result.returncode != 0, (playbook, overrides, result.stdout)
        assert not (payload / "bin").exists()


def main() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "README.md").write_text(
        "# NFS integration scratch\n\n"
        "The integration probe renders real playbooks into temporary directories "
        "here.\n"
        "Packages and activation are bypassed; no live exports or mounts are created.\n"
    )
    with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
        root = Path(directory)
        test_default_export(root / "export")
        test_default_mount(root / "mount")
        test_custom_mount(root / "custom")
        test_reject_usermode(root / "rejected")
        test_reject_root_paths(root / "rejected-root")
        test_reject_unsafe_declarations(root / "rejected-unsafe")
    print("ok: NFS export, automount, overrides, and system-scope boundary")


if __name__ == "__main__":
    main()
