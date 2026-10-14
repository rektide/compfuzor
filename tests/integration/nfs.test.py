#!/usr/bin/env python3
"""Render the real NFS playbooks in scratch space; never install or mount.

Run: python3 tests/integration/nfs.test.py
"""

from __future__ import annotations

from collections.abc import Callable
import json
import os
from pathlib import Path
import re
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


def stage_mock_install(
    payload: Path,
) -> tuple[Callable[[], subprocess.CompletedProcess[str]], Callable[[], str]]:
    """Shim sudo/exportfs/systemctl/links.mjs over a rendered payload.

    Nothing live runs: the shims record every privileged command to a
    payload-local log instead of touching /etc, systemd, or the kernel
    export table. Returns (install, commands) — run the generated
    bin/install-nfs-export.sh with the shims first on PATH, and read the
    recorded command log.
    """
    shims = payload / "shims"
    shims.mkdir()
    sudo = shims / "sudo"
    sudo.write_text('#!/bin/sh\nexec "$@"\n')
    sudo.chmod(0o755)
    logger = (
        '#!/bin/sh\n'
        'printf "%s %s\\n" "${0##*/}" "$*" >> "$NFS_TEST_LOG"\n'
    )
    for command in (shims / "systemctl", shims / "exportfs",
                    payload / "bin/links.mjs"):
        command.unlink(missing_ok=True)
        command.write_text(logger)
        command.chmod(0o755)
    log = payload / "commands.log"
    environment = {
        **os.environ, "DIR": str(payload), "ENV_BYPASS": "1",
        "PATH": f"{shims}:{os.environ['PATH']}", "NFS_TEST_LOG": str(log),
    }
    installer = payload / "bin/install-nfs-export.sh"

    def install() -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(installer)], env=environment, capture_output=True, text=True,
            check=False,
        )

    def commands() -> str:
        return log.read_text()

    return install, commands


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


def test_custom_export_installer(payload: Path) -> None:
    source = payload.parent / "source-data"
    require_success(render("nfs-export.srv.pb", payload, {
        "clients": ["127.0.0.1", "*.example.test"],
        "export_path": str(source), "export_mode": "0750",
    }))
    # Force a glob collision: client wildcard names must never become local
    # filenames, including under the generated helper's nullglob setting.
    (payload / "matched.example.test").touch()
    install, commands_log = stage_mock_install(payload)

    require_success(install())
    commands = commands_log()
    assert commands.index("links.mjs apply") < commands.index("systemctl")
    assert f"*.example.test:{source}" in commands
    assert "matched.example.test" not in commands
    assert "exportfs -i -o" in commands and "exportfs -r" not in commands
    assert source.stat().st_uid == os.getuid()
    assert source.stat().st_mode & 0o777 == 0o750
    source.chmod(0o700)
    marker = source / "preserve"
    marker.write_text("existing data\n")
    require_success(install())
    assert source.stat().st_mode & 0o777 == 0o700
    assert marker.read_text() == "existing data\n"
    before = commands_log()
    (payload / "bin/links.mjs").unlink()
    rejected = install()
    assert rejected.returncode != 0 and "no links runtime" in rejected.stderr
    assert commands_log() == before


def test_two_instances_coexist(payload: Path) -> None:
    """Two nfs-export deployments render and install side by side.

    Alpha and beta render into separate scratch payloads with distinct
    fragments and /etc/exports.d destinations. Mock-installing beta after
    alpha must leave alpha's staged fragment and command log untouched:
    each install converges only its own (client, path) entries with
    scoped `exportfs -i`, and never issues an unexport/global re-export
    or an nfs-server restart. The shared distro nfs-server start (and the
    manager daemon-reload that publishes new exports.d fragments) is the
    expected cross-deployment action.
    """
    declarations = {
        "alpha": {
            "export_path": str(payload / "export-alpha"),
            "clients": ["10.0.0.0/24"],
        },
        "beta": {
            "export_path": str(payload / "export-beta"),
            "clients": ["192.168.0.0/24", "filer.example.test"],
        },
    }
    opts = "rw,sync,no_subtree_check,root_squash"
    payloads = {}
    fragments = {}
    dests = {}
    for instance, declared in declarations.items():
        target = payload / instance
        require_success(render("nfs-export.srv.pb", target, {
            "INSTANCE": instance, **declared,
        }))
        payloads[instance] = target
        dests[instance] = f"/etc/exports.d/nfs-export-{instance}.exports"
        staged = target / "etc" / f"nfs-export-{instance}.exports"
        text = staged.read_text()
        fragments[instance] = (staged, text)
        assert list((target / "etc").rglob("*.exports")) == [staged]
        expected = declared["export_path"] + "".join(
            f" {client}({opts})" for client in declared["clients"]
        )
        assert expected in text
        plan = json.loads((target / "links.json").read_text())
        export_rows = [
            (row["src"], row["dest"]) for row in plan["links"]
            if row["dest"].startswith("/etc/exports.d/")
        ]
        assert export_rows == [(str(staged), dests[instance])]
    assert fragments["alpha"][1] != fragments["beta"][1]
    alpha_path = declarations["alpha"]["export_path"]
    beta_path = declarations["beta"]["export_path"]
    assert alpha_path not in fragments["beta"][1]
    assert beta_path not in fragments["alpha"][1]

    installers = {}
    logs = {}
    for instance in ("alpha", "beta"):
        installers[instance], logs[instance] = stage_mock_install(
            payloads[instance]
        )
    for instance in ("alpha", "beta"):
        require_success(installers[instance]())
    first_pass = {i: logs[i]() for i in ("alpha", "beta")}

    # Every logged command stays scoped: each exportfs invocation is
    # exactly `-i -o <opts> <client>:<path>` (no -r/-a/-u reconciliation,
    # and no room for an option token to leak out of a client spec), and
    # the only systemctl actions are the manager daemon-reload and the
    # shared distro enable --now. Publication precedes both.
    for instance, logged in first_pass.items():
        for line in logged.splitlines():
            if line.startswith("exportfs "):
                assert re.fullmatch(rf"exportfs -i -o {opts} \S+:\S+", line), (
                    line
                )
            if line.startswith("systemctl ") and "daemon-reload" not in line:
                assert line == "systemctl enable --now nfs-server.service", (
                    line
                )
        assert f"links.mjs apply --id system:{dests[instance]}" in logged
        published = logged.index("links.mjs apply")
        assert published < logged.index("enable --now")
        assert logged.index("enable --now") < logged.index("exportfs -i")
        if "daemon-reload" in logged:
            assert published < logged.index("daemon-reload")
    assert f"exportfs -i -o {opts} 10.0.0.0/24:{alpha_path}" in (
        first_pass["alpha"]
    )
    assert f"exportfs -i -o {opts} 192.168.0.0/24:{beta_path}" in (
        first_pass["beta"]
    )
    assert "filer.example.test:" in first_pass["beta"]
    assert "alpha" not in first_pass["beta"]
    assert "nfs-export-beta" not in first_pass["alpha"]

    # Beta left alpha exactly as alpha left it, and alpha re-converges
    # afterwards with the same scoped commands and fragment.
    staged_alpha, alpha_text = fragments["alpha"]
    assert staged_alpha.read_text() == alpha_text
    assert logs["alpha"]() == first_pass["alpha"]
    require_success(installers["alpha"]())
    assert staged_alpha.read_text() == alpha_text
    assert logs["alpha"]().count(f"10.0.0.0/24:{alpha_path}") == 2
    assert fragments["beta"][0].read_text() == fragments["beta"][1]


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
        ("nfs-export.srv.pb", {"clients": ["-option"]}),
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
        test_custom_export_installer(root / "custom-export")
        test_two_instances_coexist(root / "coexist")
        test_reject_usermode(root / "rejected")
        test_reject_root_paths(root / "rejected-root")
        test_reject_unsafe_declarations(root / "rejected-unsafe")
    print("ok: NFS export, automount, overrides, and system-scope boundary")


if __name__ == "__main__":
    main()
