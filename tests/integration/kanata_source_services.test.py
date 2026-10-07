#!/usr/bin/env python3
"""Source-lane service prep: canonical unit, owned identity, no Debian dependency.

Regression fence for the kanata source migration (design/kanata-source/):
kanata.srv.pb / kanata-blueturn.srv.pb / kinata.srv.pb must render their
units, configs, and sysusers fragments into scratch domain roots -- never
the live deployment -- declare the shared _kanata identity exactly once
(kanata.srv.pb), carry no Debian kanata package dependency, run the source
binary at /usr/local/bin/kanata under the unchanged hardening schema, and
keep the authored config bodies byte-for-byte.

Every render redirects SRVS_DIR + ETCS_DIR into a temporary scratch root
and bypasses every side-effecting phase (packages, bin execution, global
links, systemd thunk). A live fence snapshots the deployed kanata
artifacts and the _kanata account before/after and fails on any drift --
the render must not even regenerate the live config, because /etc/kanata/
config.kbd symlinks at the ETC_FILES target and a live render would
overwrite it (the authored body carries the not-yet-adopted Kinesis
exclusion).
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "kanata-source"

MAIN = "kanata.srv.pb"
HELPERS = ("kanata-blueturn.srv.pb", "kinata.srv.pb")
OWNED = (MAIN, *HELPERS)

# The retired /usr/lib/systemd/system/kanata.service schema (the helpers
# already carried it; main adopts it verbatim modulo identity + ExecStart).
HARDENING_LINES = (
    "DeviceAllow=/dev/uinput rw",
    "DeviceAllow=char-input",
    "DeviceAllow=/dev/stdin",
    "DevicePolicy=strict",
    "PrivateDevices=True",
    "BindPaths=/dev/uinput",
    "BindReadOnlyPaths=/dev/stdin",
    "BindReadOnlyPaths=/dev/input/",
    "BindReadOnlyPaths=/etc/kanata/",
    "InaccessiblePaths=/dev/shm",
    "LockPersonality=True",
    "NoNewPrivileges=True",
    "PrivateTmp=True",
    "PrivateNetwork=True",
    "PrivateUsers=True",
    "ProtectHome=True",
    "ProtectHostname=True",
    "ProtectKernelTunables=True",
    "ProtectKernelModules=True",
    "ProtectKernelLogs=True",
    "ProtectSystem=strict",
    "ProtectControlGroups=True",
    "RestrictAddressFamilies=AF_AX25",
    "RestrictAddressFamilies=~AF_AX25",
    "RestrictNamespaces=True",
    "SystemCallArchitectures=native",
    "SystemCallErrorNumber=EPERM",
    "SystemCallFilter=@system-service",
    "SystemCallFilter=~@privileged",
    "SystemCallFilter=~@resources",
    "RemoveIPC=True",
    "IPAddressDeny=any",
    "RestrictSUIDSGID=True",
    "RestrictRealtime=True",
    "MemoryDenyWriteExecute=True",
    "UMask=0077",
)

LIVE_FENCE_DIRS = (
    "/etc/opt/kanata-main",
    "/etc/opt/kanata-blueturn",
    "/etc/opt/kanata-kinata",
    "/srv/kanata-main",
    "/srv/kanata-blueturn",
    "/srv/kanata-kinata",
    "/etc/kanata",
)


def run(*command: str, cwd: Path = ROOT, env: dict[str, str] | None = None, check: bool = True) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, check=False)
    if check and result.returncode:
        raise AssertionError(f"{command} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def playbook_vars(playbook: Path) -> dict:
    plays = yaml.safe_load(playbook.read_text())
    return plays[0].get("vars", {})


def render(playbook: str, tmp: Path) -> tuple[Path, Path]:
    """Render one owned playbook into isolated scratch roots, all
    side-effecting phases bypassed. Returns (srv_root, etc_root)."""
    srv, etc = tmp / "srv", tmp / "etc_opt"
    env = os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")}
    run(
        "ansible-playbook", "-i", "localhost,", "-c", "local", playbook,
        f"-e SRVS_DIR={srv}", f"-e ETCS_DIR={etc}",
        "-e PKGS_BYPASS=True", "-e APT_BYPASS=True",
        "-e SYSTEMD_THUNK_BYPASS=True", "-e BINS_RUN_BYPASS=True",
        "-e GLOBAL_BINS_BYPASS=True",
        env=env,
    )
    return srv, etc


def unit_sections(unit_text: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current = None
    for line in unit_text.splitlines():
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections[current] = []
        elif current is not None and line.strip():
            sections[current].append(line)
    return sections


def service_keys(unit_text: str) -> set[str]:
    return {line.split("=", 1)[0] for line in unit_sections(unit_text)["Service"]}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_state(path: Path) -> dict[str, str]:
    """path -> sha256 (files) or 'link:target' (symlinks) for a fence snapshot."""
    state: dict[str, str] = {}
    if not path.exists() and not path.is_symlink():
        return state
    if path.is_symlink():
        return {str(path): f"link:{os.readlink(path)}"}
    for item in sorted(path.rglob("*")):
        if item.is_dir() and not item.is_symlink():
            continue
        key = str(item)
        state[key] = f"link:{os.readlink(item)}" if item.is_symlink() else sha(item)
    return state


def live_fence_snapshot() -> dict:
    dirs = {name: tree_state(Path(name)) for name in LIVE_FENCE_DIRS}
    unit_glob = {str(p): f"link:{os.readlink(p)}" if p.is_symlink() else sha(p)
                 for p in Path("/etc/systemd/system").glob("kanata*")}
    unit_glob |= {str(p): f"link:{os.readlink(p)}" if p.is_symlink() else sha(p)
                  for p in Path("/etc/systemd/system").glob("kinata*")}
    sysusers = {str(p): f"link:{os.readlink(p)}" if p.is_symlink() else sha(p)
                for p in Path("/etc/sysusers.d").glob("kanata*")}
    passwd = run("getent", "passwd", "_kanata", check=False)
    group = run("getent", "group", "_kanata", check=False)
    return {"dirs": dirs, "units": unit_glob, "sysusers": sysusers,
            "passwd": passwd, "group": group}


def assert_unchanged(before: dict, after: dict, label: str) -> None:
    for key in before:
        if before[key] != after.get(key):
            raise AssertionError(
                f"{label}: live state changed during scratch render: {key}\n"
                f"  before: {before[key]!r}\n  after:  {after.get(key)!r}"
            )
    for key in after:
        if key not in before:
            raise AssertionError(f"{label}: live path created during scratch render: {key}")


def assert_identity_consumer(unit_text: str, config: str) -> None:
    """Shared shape for all three units: static identity, input access,
    source binary, package hardening, no alias, no restart policy,
    no loosened network sandbox."""
    service = unit_sections(unit_text)["Service"]
    for line in ("User=_kanata", "Group=_kanata", "SupplementaryGroups=input",
                 f"ExecStart=/usr/local/bin/kanata --cfg {config}"):
        if line not in service:
            raise AssertionError(f"missing unit line: {line}\n{unit_text}")
    for line in HARDENING_LINES:
        if line not in service:
            raise AssertionError(f"missing hardening line: {line}\n{unit_text}")
    if any(line.startswith("Restart=") for line in service):
        raise AssertionError(f"restart policy changed from the packaged no-op:\n{unit_text}")
    if any(line.startswith("Alias=") for line in unit_sections(unit_text).get("Install", [])):
        raise AssertionError(f"alias on a non-canonical unit would fight kanata.service:\n{unit_text}")
    for loosened in ("AF_INET", "AF_UNIX", "ListenStream", "IPAddressAllow"):
        if loosened in unit_text:
            raise AssertionError(f"network sandbox loosened ({loosened}); TCP capability != listener:\n{unit_text}")


def test_no_debian_package_dependency() -> None:
    for name in OWNED:
        variables = playbook_vars(ROOT / name)
        for key in ("PKGS", "PKGSET", "PKGSETS"):
            packages = variables.get(key) or []
            if "kanata" in packages:
                raise AssertionError(f"{name}: {key} still installs the Debian kanata package")
        for key in ("SYSUSERS", "SYSTEMD_SYSUSER"):
            if name != MAIN and key in variables:
                raise AssertionError(f"{name}: helper must consume, not declare, _kanata ({key})")


def test_identity_declared_exactly_once() -> None:
    declarers = []
    for playbook in sorted(ROOT.rglob("*.pb")):
        text = playbook.read_text()
        if "_kanata" not in text:
            continue
        try:
            variables = playbook_vars(playbook)
        except yaml.YAMLError as error:
            raise AssertionError(f"{playbook} references _kanata but will not parse: {error}") from error
        specs = variables.get("SYSUSERS") or []
        if not isinstance(specs, list):
            specs = [specs]
        for spec in specs:
            entry = {"name": spec} if isinstance(spec, str) else spec or {}
            if entry.get("name") == "_kanata" and not entry.get("member"):
                declarers.append(str(playbook))
                break
        else:
            services = variables.get("SYSTEMD_SERVICES") or {}
            if variables.get("SYSTEMD_SYSUSER") and services.get("User") == "_kanata":
                declarers.append(str(playbook))
    if declarers != [str(ROOT / MAIN)]:
        raise AssertionError(f"_kanata identity must be declared by {MAIN} alone, got: {declarers}")


def main() -> None:
    test_no_debian_package_dependency()
    test_identity_declared_exactly_once()

    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SCRATCH, prefix="services-") as directory:
        tmp = Path(directory)
        fence_before = live_fence_snapshot()

        srv, etc = render(MAIN, tmp)
        main_etc = etc / "kanata-main"
        main_bin = srv / "kanata-main" / "bin"

        # canonical unit identity: kanata.service, never a competing name
        unit = main_etc / "kanata.service"
        if not unit.is_file():
            raise AssertionError(f"main must render the canonical unit, missing: {unit}")
        stale = main_etc / "kanata-main.service"
        if stale.exists():
            raise AssertionError(f"rendered a differently named unit competing with kanata.service: {stale}")
        unit_text = unit.read_text()
        assert_identity_consumer(unit_text, "/etc/kanata/config.kbd")
        unit_section = unit_sections(unit_text)
        if "Description=Kanata keyboard remapper" not in unit_section["Unit"]:
            raise AssertionError(f"packaged Description not mirrored:\n{unit_text}")
        if "WantedBy=default.target" not in unit_section["Install"]:
            raise AssertionError(f"packaged [Install] target not retained:\n{unit_text}")

        # static account: sysusers fragment pins this host's uid/gid/input
        fragment = main_etc / "sysusers.d" / "kanata-main.conf"
        expected = (
            'u _kanata 990:985 "Kanata daemon" /nonexistent /usr/sbin/nologin\n'
            "m _kanata input\n"
        )
        if not fragment.is_file() or fragment.read_text() != expected:
            raise AssertionError(
                f"sysusers fragment must pin the live uid/gid verbatim:\n{fragment}\n"
                f"expected:\n{expected}\ngot:\n{fragment.read_text() if fragment.exists() else '<missing>'}"
            )

        # install surface: canonical unit script + identity lane, no apt lane
        for script in ("install-service-kanata.sh", "install-sysusers.sh", "install-unit.sh"):
            if not (main_bin / script).is_file():
                raise AssertionError(f"missing main install script: {main_bin / script}")
        for script in ("install-apt.sh", "status-apt.sh"):
            if (main_bin / script).exists():
                raise AssertionError(f"apt lane generated without PKGS: {main_bin / script}")

        # link plan: unit + fragment + config records present for the
        # future handoff; nothing here applies them
        plan = json.loads((srv / "kanata-main" / "links.json").read_text())
        dests = {link["dest"] for link in plan["links"]}
        for dest in ("/etc/systemd/system/kanata.service",
                     "/etc/sysusers.d/kanata-main.conf",
                     "/etc/kanata/config.kbd"):
            if dest not in dests:
                raise AssertionError(f"link record for {dest} missing from plan: {dests}")

        # authored config body unchanged (binding + device bodies)
        config = (main_etc / "kanata.kbd").read_text()
        for needle in ('linux-dev-names-exclude (',
                       '"iRig BlueTurn Keyboard"',
                       '"Kinesis Freestyle Edge RGB Keyboard"',
                       "(defsrc",
                       "caps",
                       "(tap-hold 100 100 esc lctl)"):
            if needle not in config:
                raise AssertionError(f"authored main config body changed (missing {needle!r})")

        helper_keys = service_keys(unit_text)
        for helper, helper_name, config_name, include in (
            ("kanata-blueturn.srv.pb", "kanata-blueturn", "blueturn.kbd", '"iRig BlueTurn Keyboard"'),
            ("kinata.srv.pb", "kanata-kinata", "kinata.kbd", '"Kinesis Freestyle Edge RGB Keyboard"'),
        ):
            render(helper, tmp)
            helper_unit = etc / helper_name / f"{helper_name}.service"
            if not helper_unit.is_file():
                raise AssertionError(f"helper unit missing: {helper_unit}")
            helper_text = helper_unit.read_text()
            assert_identity_consumer(helper_text, f"/etc/kanata/{config_name}")
            if service_keys(helper_text) != helper_keys:
                raise AssertionError(
                    f"{helper} hardening schema drifted from main:\n"
                    f"main:    {sorted(helper_keys)}\n{helper}: {sorted(service_keys(helper_text))}"
                )
            helper_bin = srv / helper_name / "bin"
            if not (helper_bin / "install-service.sh").is_file():
                raise AssertionError(f"helper unit-name install script missing: {helper_bin}/install-service.sh")
            if (helper_bin / "install-apt.sh").exists() or (helper_bin / "status-apt.sh").exists():
                raise AssertionError(f"apt lane generated for {helper} without PKGS")
            helper_plan = json.loads((srv / helper_name / "links.json").read_text())
            helper_dests = {link["dest"] for link in helper_plan["links"]}
            if f"/etc/systemd/system/{helper_name}.service" not in helper_dests:
                raise AssertionError(f"{helper} unit link record missing: {helper_dests}")
            helper_config = (etc / helper_name / "kanata.kbd").read_text()
            for needle in ("linux-dev-names-include (", include):
                if needle not in helper_config:
                    raise AssertionError(f"{helper} authored config body changed (missing {needle!r})")
            # blueturn is deployed: its authored body must still render
            # byte-identical to the live config
            live_config = Path(f"/etc/opt/{helper_name}/kanata.kbd")
            if helper_name == "kanata-blueturn" and live_config.is_file():
                if sha(live_config) != hashlib.sha256(helper_config.encode()).hexdigest():
                    raise AssertionError("blueturn authored config drifted from the live deployment")

        assert_unchanged(fence_before, live_fence_snapshot(), "live fence")

    print("ok: kanata source services (canonical unit, one identity declarer, "
          "no Debian dependency, configs unchanged, live deployment untouched)")


if __name__ == "__main__":
    main()
