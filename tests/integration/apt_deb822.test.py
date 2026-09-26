#!/usr/bin/env python3
"""Deb822 generation and unprivileged publication into sandbox paths."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "apt-deb822"
sys.path.insert(0, str(ROOT / "library/filter_plugins"))
from apt_sources import apt_sources  # noqa: E402


def render(name, overrides, expect_failure=False):
    root = SCRATCH / name
    for directory in (root / "etc", root / "bin", root / "sources", root / "preferences", root / "keyrings"):
        directory.mkdir(parents=True, exist_ok=True)
    if "ETC" in overrides:
        Path(overrides["ETC"]).mkdir(parents=True, exist_ok=True)
    for output in (
        root / "sources/apt-probe-main.sources", root / "preferences/apt-probe-main.pref",
        root / "keyrings/chrome-apt.gpg", root / "keyrings/test-key.gpg",
        root / "etc/chrome-apt.gpg", root / "etc/test-key.gpg",
    ):
        if output.is_file() or output.is_symlink():
            output.unlink()
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "README.md").write_text("# apt-deb822 tests\n\nSandboxed render and publication probes.\n")
    for child in ("vars", "files"):
        link = SCRATCH / child
        if not link.exists():
            link.symlink_to(ROOT / child, target_is_directory=True)
    playbook = SCRATCH / "probe.pb"
    playbook.write_text(
        """---
- hosts: all
  gather_facts: false
  vars_files:
    - {common}
  vars:
    TYPE: apt-probe
    NAME: apt-probe-main
    ETC: {etc}
    ETC_FILES: []
    BINS: []
    STATUSES: []
    APT_SOURCES_DIR: {sources}
    APT_PREFERENCES_DIR: {preferences}
    APT_KEYRINGS_DIR: {keyrings}
    APT_BECOME: false
    APT_UPDATE_BYPASS: true
  tasks:
    - import_tasks: {vars_apt}
    - copy:
        dest: "{{{{ ETC }}}}/../source-name"
        content: "{{{{ APT_SOURCELIST }}}}"
    - import_tasks: {gen}
      when: APT is defined or APTS is defined
    - import_tasks: {gen_apt}
      when: PKGS is defined
    - import_tasks: {gen_bins}
    - copy:
        dest: "{{{{ ETC }}}}/../bin/install-apt-sources.sh"
        content: "{{{{ item.generated }}}}"
        mode: "0755"
      loop: "{{{{ BINS | selectattr('name', 'equalto', 'install-apt-sources.sh') | list }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/../bins.json"
        content: "{{{{ BINS | to_json }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/{{{{ item.name }}}}"
        content: "{{{{ item.content }}}}"
        mode: "0644"
      loop: "{{{{ ETC_FILES | selectattr('content', 'defined') | list }}}}"
    - copy:
        dest: "{{{{ ETC }}}}/{{{{ item.name }}}}"
        src: "{{{{ item.src }}}}"
        mode: "0644"
      loop: "{{{{ ETC_FILES | selectattr('src', 'defined') | list }}}}"
    - import_tasks: {deliver}
      when: (APT is defined or APTS is defined) and not APT_BYPASS | default(false) | bool
""".format(
            common=ROOT / "vars/common.yaml", etc=root / "etc", sources=root / "sources",
            preferences=root / "preferences", keyrings=root / "keyrings",
            vars_apt=ROOT / "tasks/compfuzor/vars_apt.tasks",
            gen=ROOT / "tasks/compfuzor/gen_apt_sources.tasks",
            gen_apt=ROOT / "tasks/compfuzor/gen_apt.tasks",
            gen_bins=ROOT / "tasks/compfuzor/gen_bins.tasks",
            deliver=ROOT / "tasks/compfuzor/apt_deb822.tasks",
        )
    )
    (SCRATCH / "vars.json").write_text(json.dumps({"TYPE": "apt-probe", "NAME": "apt-probe-main", **overrides}))
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook), "-e", f"@{SCRATCH / 'vars.json'}"],
        cwd=ROOT, env={**os.environ, "HOME": str(SCRATCH)}, text=True, capture_output=True,
    )
    if expect_failure:
        assert result.returncode, result.stdout + result.stderr
    else:
        assert result.returncode == 0, result.stdout + result.stderr
    return root, result.stdout + result.stderr


def test_sources_override_legacy():
    root, log = render("source-only", {
        "APT": {"URIs": "https://example.org/repo", "Suites": "stable", "By-Hash": "yes"},
        "APT_REPO": "https://legacy.example.org/repo",
        "APT_LIST_URL": "https://legacy.example.org/apt.list",
        "APT_PIN": "release n=legacy", "APT_PIN_PRIORITY": 200,
        "APT_PREFS": {"Pin": "release n=stable", "Pin-Priority": 600},
    })
    source = root / "sources/apt-probe-main.sources"
    assert source.is_symlink()
    assert "By-Hash: yes" in source.read_text()
    assert "legacy.example.org" not in source.read_text()
    assert not (root / "sources/apt-probe-main.list").exists()
    assert (root / "preferences/apt-probe-main.pref").read_text() == "Package: *\nPin: release n=stable\nPin-Priority: 600\n"
    assert "ignoring legacy" in log
    assert "APT_REPO" in log and "APT_PIN" in log

    # The install-time leaf works even when there are no PKGS, and the
    # render-time APT_BYPASS does not gate generation.
    source.unlink()
    (root / "preferences/apt-probe-main.pref").unlink()
    command = ["bash", "-euo", "pipefail", str(root / "bin/install-apt-sources.sh")]
    env = {**os.environ, "DIR": str(root), "COMPFUZOR_APT_SUDO": "", "COMPFUZOR_APT_UPDATE_BYPASS": "1"}
    subprocess.run(command, cwd=ROOT, env=env, check=True)
    assert source.is_symlink() and (root / "preferences/apt-probe-main.pref").is_symlink()
    assert "install-apt-sources.sh" in [record["name"] for record in json.loads((root / "bins.json").read_text())]
    source.unlink()
    source.write_text("foreign source\n")
    foreign = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    assert foreign.returncode != 0 and "foreign apt file" in foreign.stderr
    assert source.read_text() == "foreign source\n"


def test_sources_before_packages():
    root, _ = render("packages", {"APT": {"URIs": "https://example.org"}, "PKGS": ["jq"]})
    bins = json.loads((root / "bins.json").read_text())
    install = next(record for record in bins if record["name"] == "install.sh")
    assert install["run_all"].index("install-apt-sources.sh") < install["run_all"].index("install-apt.sh")


def test_materialized_etc_matches_both_delivery_passes():
    root = SCRATCH / "external-etc"
    materialized = root / "materialized"
    rendered, _ = render("external-etc", {"APT": {"URIs": "https://example.org"}, "ETC": str(materialized)})
    source = rendered / "sources/apt-probe-main.sources"
    assert source.is_symlink() and source.readlink() == materialized / "apt-probe-main.sources"
    env = {**os.environ, "DIR": str(rendered), "COMPFUZOR_APT_SUDO": "", "COMPFUZOR_APT_UPDATE_BYPASS": "1"}
    subprocess.run(["bash", "-euo", "pipefail", str(rendered / "bin/install-apt-sources.sh")], cwd=ROOT, env=env, check=True)
    assert source.readlink() == materialized / "apt-probe-main.sources"


def test_bypass_and_vendor_key():
    root, _ = render("bypassed", {
        "APT": {"URIs": "https://example.org"}, "APT_TRUSTED": "chrome-apt", "APT_BYPASS": True,
    })
    assert not (root / "sources/apt-probe-main.sources").exists()
    assert "Signed-By: " + str(root / "keyrings/chrome-apt.gpg") in (root / "etc/apt-probe-main.sources").read_text()
    assert (root / "etc/chrome-apt.gpg").is_file()
    (root / "etc").chmod(0o700)
    env = {**os.environ, "DIR": str(root), "COMPFUZOR_APT_SUDO": "", "COMPFUZOR_APT_UPDATE_BYPASS": "1"}
    subprocess.run(["bash", "-euo", "pipefail", str(root / "bin/install-apt-sources.sh")], cwd=ROOT, env=env, check=True)
    assert (root / "etc").stat().st_mode & 0o005 == 0o005
    assert (root / "keyrings/chrome-apt.gpg").is_symlink()
    assert (root / "sources/apt-probe-main.sources").is_symlink()


def test_url_key_dearmor_at_install_time():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    armored = SCRATCH / "test-key.asc"
    with armored.open("w") as output:
        subprocess.run(
            ["gpg", "--no-default-keyring", "--keyring", str(ROOT / "files/apt-repos/chrome-apt.gpg"), "--armor", "--export"],
            stdout=output, check=True,
        )
    root, _ = render("url-key", {
        "APT": {"URIs": "https://example.org"}, "APT_KEYRING_URL": armored.as_uri(),
        "APT_DEARMOR": True, "APT_BYPASS": True, "APT_TRUSTED": "test-key",
    })
    assert not (root / "etc/test-key.gpg").exists()
    env = {**os.environ, "DIR": str(root), "COMPFUZOR_APT_SUDO": "", "COMPFUZOR_APT_UPDATE_BYPASS": "1"}
    subprocess.run(["bash", "-euo", "pipefail", str(root / "bin/install-apt-sources.sh")], cwd=ROOT, env=env, check=True)
    assert (root / "etc/test-key.gpg").read_bytes()[:1] != b"-"
    assert (root / "keyrings/test-key.gpg").is_symlink()


def test_invalid_empty_apt_does_not_fall_back():
    _, log = render("empty", {"APT": {}, "APT_REPO": "https://legacy.example.org"}, True)
    assert "requires URIs" in log


def test_apts_only_and_legacy_name():
    root, _ = render("multiple", {
        "APTS": [
            {"URIs": "https://one.example.org", "Suites": "stable"},
            {"URIs": "https://two.example.org", "Suites": "/", "Components": [], "Enabled": False},
        ],
        "APT_REPO": "https://ignored.example.org",
    })
    text = (root / "sources/apt-probe-main.sources").read_text()
    assert text.count("URIs:") == 2 and "Enabled: no" in text
    assert "Components: main" in text.split("\n\n")[0]
    assert "Components:" not in text.split("\n\n")[1]
    assert "ignored.example.org" not in text
    assert (root / "source-name").read_text() == "apt-probe-main"

    old, _ = render("legacy-name", {"APT_REPO": "https://old.example.org"})
    assert (old / "source-name").read_text() == "apt-probe"


def test_apt_accepts_inline_signed_by():
    """APT's actual deb822 parser accepts the encoded multiline keyblock."""
    key = subprocess.run(
        ["gpg", "--no-default-keyring", "--keyring", str(ROOT / "files/apt-repos/chrome-apt.gpg"), "--armor", "--export"],
        check=True, capture_output=True, text=True,
    ).stdout
    SCRATCH.mkdir(parents=True, exist_ok=True)
    source = SCRATCH / "inline.sources"
    source.write_text(apt_sources([{"URIs": "https://example.org", "Signed-By": key}], {"Suites": "stable", "Components": "main"}))
    result = subprocess.run(
        ["apt-get", "indextargets", "-o", f"Dir::Etc::sourcelist={source}", "-o", "Dir::Etc::sourceparts=-"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr


if __name__ == "__main__":
    test_sources_override_legacy()
    test_sources_before_packages()
    test_materialized_etc_matches_both_delivery_passes()
    test_bypass_and_vendor_key()
    test_url_key_dearmor_at_install_time()
    test_invalid_empty_apt_does_not_fall_back()
    test_apts_only_and_legacy_name()
    test_apt_accepts_inline_signed_by()
    print("ok: deb822 source render and precedence")
