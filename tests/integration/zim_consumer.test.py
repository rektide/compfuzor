#!/usr/bin/env python3
"""Render the real Zim host and prove donor/admin/consumer lifecycle separation."""

from __future__ import annotations

from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from zim_demo import write_environment_wrapper


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "config-contexts"
NODE = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def render_host(payload: Path, scenario: Path, ansible_env: dict[str, str]) -> None:
    values = {
        "TYPE": "zim",
        "NAME": "zim-main",
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
        "ZIM_MODULES": [
            {"source": "environment", "phase": "core"},
            {"source": "minimal", "phase": "prompt", "enabled": False},
            {"source": "rektide/zim-mise", "phase": "core", "channel": "zimenv"},
        ],
    }
    scenario.write_text(json.dumps(values), encoding="utf-8")
    run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(ROOT / "zim.opt.pb"), "-e", f"@{scenario}"],
        cwd=ROOT,
        env=ansible_env,
    )


def render_producer(payload: Path, playbook: Path, ansible_env: dict[str, str]) -> None:
    (playbook.parent / "files").symlink_to(ROOT / "files", target_is_directory=True)
    (playbook.parent / "vars").symlink_to(ROOT / "vars", target_is_directory=True)
    playbook.write_text(
        f"""---
- hosts: all
  gather_facts: false
  vars_files: [{str(ROOT / 'vars' / 'common.yaml')!r}]
  vars:
    TYPE: producer
    NAME: producer-main
    INSTANCE: main
    DIR: {str(payload)!r}
    ETC: {str(payload / 'etc')!r}
    BINS_DIR: {str(payload / 'bin')!r}
    BINS: []
    ETC_FILES: []
    ETC_DIRS: []
    DIRS: []
    ENV: {{}}
    ENV_LIST: []
    STATUSES: []
    ZIM_BYPASS: false
    ZIM_MODULES:
      - source: producer-rc
        phase: tools
      - source: producer-env
        phase: tools
        channel: zimenv
        enabled: false
  tasks:
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_zim.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'gen_bins.tasks')!r}
    - file:
        path: "{{{{ item }}}}"
        state: directory
      loop: "{{{{ [ETC, BINS_DIR] + (ETC_DIRS | map('defaultDir', ETC) | list) }}}}"
    - copy:
        dest: "{{{{ item.name | defaultDir(ETC) }}}}"
        content: "{{{{ item.content }}}}"
        mode: '0600'
      loop: "{{{{ ETC_FILES }}}}"
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins.tasks')!r}
    - import_tasks: {str(ROOT / 'tasks' / 'compfuzor' / 'bins_link.tasks')!r}
""",
        encoding="utf-8",
    )
    run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
        cwd=ROOT,
        env=ansible_env,
    )


def user_env(home: Path, xdg: Path, zdotdir: Path, payload: Path, build_log: Path, block_in_file: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(xdg),
        "ZDOTDIR": str(zdotdir),
        "ZIM_HOME": str(home / ".cache" / "zim"),
        "ZIM_ENV_HOME": str(home / ".cache" / "zim-env"),
        "ZIM_TEST_BUILD_LOG": str(build_log),
        "CONFIG_BLOCK_IN_FILE": str(block_in_file),
        "DIR": str(payload),
        "TMPDIR": str(SCRATCH),
        "PATH": os.pathsep.join((str(Path(NODE).parent), str(block_in_file.parent), "/usr/bin", "/bin")),
    })
    for name in ("ZIM_CONFIG_FILE", "ZIM_ENV_CONFIG", "ZIM_CONFIG_LINK"):
        env.pop(name, None)
    return env


def donor_digest(payload: Path) -> str:
    digest = hashlib.sha256()
    for directory in (payload / "etc" / "zimrc.d", payload / "etc" / "zimenv.d"):
        for path in sorted(directory.iterdir()):
            digest.update(path.name.encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def test_zim_consumer_lifecycle() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    demo_setting = os.environ.get("COMPFUZOR_KEEP_ZIM_DEMO")
    if demo_setting:
        if demo_setting.lower() in {"1", "true", "yes"}:
            demo_root = Path(tempfile.mkdtemp(prefix="zim-demo-", dir=SCRATCH))
        else:
            demo_root = Path(demo_setting).resolve()
            if demo_root.exists() and any(demo_root.iterdir()):
                raise RuntimeError(f"refusing nonempty demo root: {demo_root}")
            demo_root.mkdir(parents=True, exist_ok=True)
        temporary_context = nullcontext(str(demo_root))
    else:
        temporary_context = tempfile.TemporaryDirectory(prefix="zim consumer migration-", dir=SCRATCH)
    with temporary_context as tmp:
        temporary = Path(tmp)
        block_in_file = temporary / "block-in-file"
        block_in_file.write_text(
            f'#!/bin/sh\nexec {NODE!r} {str(Path.home() / "src/block-in-file/dist/block-in-file.mjs")!r} "$@"\n',
            encoding="utf-8",
        )
        block_in_file.chmod(0o755)
        payload = temporary / "zim host with spaces"
        scenario = temporary / "host.json"
        ansible_env = os.environ.copy()
        ansible_env["ANSIBLE_CONFIG"] = str(ROOT / "ansible.cfg")
        render_host(payload, scenario, ansible_env)

        zimrc_d = payload / "etc" / "zimrc.d"
        zimenv_d = payload / "etc" / "zimenv.d"
        assert (zimrc_d / "20-environment.conf").is_file()
        assert (zimrc_d / "40-minimal.conf.disabled").is_file()
        assert (zimenv_d / "20-zim-mise.conf").is_file()
        assert not (payload / "etc" / "zim" / "zimrc").exists()

        precursor = payload / "etc" / "zim" / "zimrc" / "active" / "old-layout.conf"
        precursor.parent.mkdir(parents=True)
        precursor.write_text("old-layout\n", encoding="utf-8")
        render_host(payload, scenario, ansible_env)
        assert precursor.read_text(encoding="utf-8") == "old-layout\n"

        build_log = temporary / "build.log"
        controller = payload / "src" / "zimfw.zsh"
        controller.parent.mkdir(parents=True, exist_ok=True)
        controller.write_text(
            """mkdir -p -- "$ZIM_HOME"
print -r -- "# cache built from $ZIM_CONFIG_FILE" > "$ZIM_HOME/init.zsh"
print -r -- "$ZIM_CONFIG_FILE" >> "$ZIM_TEST_BUILD_LOG"
zimfw() { :; }
""",
            encoding="utf-8",
        )

        canonical_env = os.environ.copy()
        canonical_env.pop("DIR", None)
        canonical_env["CONFIG_BLOCK_IN_FILE"] = str(block_in_file)
        canonical_env["TMPDIR"] = str(SCRATCH)
        run([str(payload / "bin" / "config.sh")], cwd=payload, env=canonical_env)
        canonical_zimrc = payload / "etc" / "zimrc"
        canonical_zimenv = payload / "etc" / "zimenv"
        assert canonical_zimrc.is_file() and canonical_zimenv.is_file()

        install_user_text = (payload / "bin" / "install-user.sh").read_text(encoding="utf-8")
        ordered = [
            "install-config-user.sh",
            "install-zimenv-loader-user.sh",
            "install-zimrc-loader-user.sh",
            "install-zim-caches-user.sh",
            "install-zim-registry-user.sh",
        ]
        positions = [install_user_text.index(name) for name in ordered]
        assert positions == sorted(positions)
        assert install_user_text.count('"$DIR/bin/install-config-user.sh" "$@"') == 1
        assert "install-zim-donor" not in install_user_text

        home_one = temporary / "home one"
        xdg_one = temporary / "xdg one"
        zdot_one = temporary / "zdot one"
        zdot_one.mkdir()
        (zdot_one / ".zshenv").write_text("unmanaged-env\n", encoding="utf-8")
        (zdot_one / ".zshrc").write_text("unmanaged-rc\n", encoding="utf-8")
        env_one = user_env(home_one, xdg_one, zdot_one, payload, build_log, block_in_file)
        foreign = temporary / "foreign deployment"
        (foreign / "bin").mkdir(parents=True)
        foreign_log = temporary / "foreign-dispatch.log"
        for name in ("install-config-user.sh", "status-zim.sh", "status-config-context-user.sh"):
            path = foreign / "bin" / name
            path.write_text(f'#!/bin/sh\necho {name} >> {str(foreign_log)!r}\nexit 0\n', encoding="utf-8")
            path.chmod(0o755)
        env_one["DIR"] = str(foreign)
        # Simulate values inherited from the pre-migration env/export contract.
        env_one["ZIM_CONFIG_FILE"] = str(canonical_zimrc)
        env_one["ZIM_ENV_CONFIG"] = str(canonical_zimenv)
        before_user = donor_digest(payload)

        for path in (*zimrc_d.iterdir(), *zimenv_d.iterdir()):
            path.chmod(0o444)
        zimrc_d.chmod(0o555)
        zimenv_d.chmod(0o555)
        run([str(payload / "bin" / "install-user.sh")], cwd=temporary, env=env_one)
        assert not foreign_log.exists()

        local_root_one = xdg_one / "zsh"
        local_zimrc = local_root_one / "zimrc"
        local_zimenv = local_root_one / "zimenv"
        assert local_zimrc.is_file() and local_zimenv.is_file()
        assert canonical_zimrc.is_file() and canonical_zimenv.is_file()
        assert donor_digest(payload) == before_user
        assert (local_root_one / "zimrc.d" / "20-environment.conf").is_symlink()
        assert (local_root_one / "zimrc.d" / "40-minimal.conf.disabled").is_symlink()
        assert "unmanaged-env" in (zdot_one / ".zshenv").read_text(encoding="utf-8")
        assert "unmanaged-rc" in (zdot_one / ".zshrc").read_text(encoding="utf-8")
        assert build_log.read_text(encoding="utf-8").splitlines() == [str(local_zimenv), str(local_zimrc)]
        registry_one = local_root_one / "zimfw.conf"
        assert registry_one.is_symlink() and registry_one.resolve() == canonical_zimrc

        for marker, source, startup in (
            ("zim-main-zimenv", payload / "etc" / "zimenv.zsh", zdot_one / ".zshenv"),
            ("zim-main-zimrc", payload / "etc" / "zimrc.zsh", zdot_one / ".zshrc"),
        ):
            projected = run([str(block_in_file), "--read", "-n", marker, str(startup)], cwd=temporary, env=env_one)
            assert projected.stdout.encode() == source.read_bytes()

        no_leak = run(
            ["zsh", "-dfc", 'unset ZIM_CONFIG_FILE zimfw; source "$ZDOTDIR/.zshenv"; [[ -z ${ZIM_CONFIG_FILE+x} && -z ${functions[zimfw]+x} ]]'],
            cwd=temporary,
            env=env_one,
        )
        assert no_leak.returncode == 0

        producer = temporary / "producer"
        render_producer(producer, temporary / "producer-render.pb", ansible_env)
        producer_install = producer / "bin" / "install-user-zimfw.sh"
        assert producer_install.is_file()

        run(
            [str(payload / "bin" / "config-inputs-user.sh"), "disable", "zimrc/zimrc", "20-environment.conf"],
            cwd=temporary,
            env=env_one,
        )
        build_log.write_text("", encoding="utf-8")
        run([str(producer_install)], cwd=temporary, env=env_one)
        assert build_log.read_text(encoding="utf-8").splitlines() == [str(local_zimenv), str(local_zimrc)]
        producer_rc = local_root_one / "zimrc.d" / "55-producer-rc.conf"
        producer_env_disabled = local_root_one / "zimenv.d" / "55-producer-env.conf.disabled"
        assert producer_rc.is_symlink()
        assert producer_env_disabled.is_symlink()
        assert not (local_root_one / "zimenv.d" / "55-producer-env.conf").exists()
        assert (local_root_one / "zimrc.d" / "20-environment.conf.disabled").exists()
        assert donor_digest(payload) == before_user

        run(
            [str(payload / "bin" / "config-inputs-user.sh"), "enable", "zimenv/zimenv", "55-producer-env.conf"],
            cwd=temporary,
            env=env_one,
        )
        build_log.write_text("", encoding="utf-8")
        run([str(producer_install)], cwd=temporary, env=env_one)
        assert (local_root_one / "zimenv.d" / "55-producer-env.conf").is_symlink()
        assert not producer_env_disabled.exists()
        assert build_log.read_text(encoding="utf-8").splitlines() == [str(local_zimenv), str(local_zimrc)]

        run([str(payload / "bin" / "install-config-user-dropins-copy.sh"), "zimrc"], cwd=temporary, env=env_one)
        assert not (local_root_one / "zimrc.d" / "20-environment.conf.disabled").is_symlink()
        assert producer_rc.is_symlink()

        run([str(payload / "bin" / "install-config-user-copy.sh"), "zimrc"], cwd=temporary, env=env_one)
        assert local_zimrc.is_file() and not local_zimrc.is_symlink()
        assert local_zimrc.read_bytes() == canonical_zimrc.read_bytes()
        run([str(payload / "bin" / "install-config-user-link.sh"), "zimrc"], cwd=temporary, env=env_one)
        assert local_zimrc.is_symlink() and local_zimrc.resolve() == canonical_zimrc
        run([str(payload / "bin" / "config-user.sh"), "zimrc"], cwd=temporary, env=env_one)
        assert local_zimrc.is_file() and not local_zimrc.is_symlink()
        assert donor_digest(payload) == before_user

        home_two = temporary / "home two"
        xdg_two = temporary / "xdg two"
        zdot_two = temporary / "zdot two"
        zdot_two.mkdir()
        custom_zimrc = home_two / "custom" / "runtime.zimrc"
        custom_zimenv = home_two / "custom" / "runtime.zimenv"
        custom_registry = home_two / "registry" / "zimfw.conf"
        env_two = user_env(home_two, xdg_two, zdot_two, payload, temporary / "build-two.log", block_in_file)
        env_two.update({
            "ZIM_CONFIG_FILE": str(custom_zimrc),
            "ZIM_ENV_CONFIG": str(custom_zimenv),
            "ZIM_CONFIG_LINK": str(custom_registry),
            "DIR": str(temporary / "missing ambient deployment"),
        })
        install_two = run([str(payload / "bin" / "install-user.sh")], cwd=temporary, env=env_two)
        assert custom_zimrc.is_file() and custom_zimenv.is_file()
        assert custom_registry.is_symlink() and custom_registry.resolve() == canonical_zimrc, (install_two.stdout, install_two.stderr, list(home_two.rglob("zimfw.conf")), list(xdg_two.rglob("zimfw.conf")))
        assert not (xdg_two / "zsh" / "zimrc.d" / producer_rc.name).exists()
        assert donor_digest(payload) == before_user

        run([str(payload / "bin" / "install-zim-caches-user.sh")], cwd=temporary, env=env_one)
        clean_status = run([str(payload / "bin" / "status.sh")], cwd=temporary, env=env_one, check=False)
        assert clean_status.returncode == 0, (clean_status.stdout, clean_status.stderr)
        assert not foreign_log.exists()

        different = temporary / "different-loader.zsh"
        different.write_text("echo different\n", encoding="utf-8")
        run(
            [str(block_in_file), "-n", "zim-main-zimrc", "-i", str(different), "-o", str(zdot_one / ".zshrc")],
            cwd=temporary,
            env=env_one,
        )
        changed_loader = run([str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=env_one, check=False)
        assert changed_loader.returncode == 1 and "differs" in changed_loader.stdout
        run([str(payload / "bin" / "install-zimrc-loader-user.sh")], cwd=temporary, env=env_one)

        loader_source = payload / "etc" / "zimrc.zsh"
        loader_backup = loader_source.read_bytes()
        loader_source.unlink()
        missing_loader = run([str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=env_one, check=False)
        assert missing_loader.returncode == 1 and "block source is missing" in missing_loader.stdout
        loader_source.write_bytes(loader_backup)

        # Restore donor permissions for scratch cleanup.
        zimrc_d.chmod(0o755)
        zimenv_d.chmod(0o755)
        for path in (*zimrc_d.iterdir(), *zimenv_d.iterdir()):
            path.chmod(0o644)
        if demo_setting:
            demo_tmp = temporary / "tmp"
            demo_tmp.mkdir(exist_ok=True)
            common = {
                "CONFIG_BLOCK_IN_FILE": str(block_in_file),
                "DIR": str(payload),
                "TMPDIR": str(demo_tmp),
                "PATH": os.pathsep.join((str(Path(NODE).parent), str(block_in_file.parent), "/usr/bin", "/bin")),
            }
            write_environment_wrapper(temporary / "user-one.sh", common | {
                "HOME": str(home_one), "XDG_CONFIG_HOME": str(xdg_one), "ZDOTDIR": str(zdot_one),
                "ZIM_HOME": str(home_one / ".cache" / "zim"), "ZIM_ENV_HOME": str(home_one / ".cache" / "zim-env"),
                "ZIM_TEST_BUILD_LOG": str(build_log),
            })
            write_environment_wrapper(temporary / "user-two.sh", common | {
                "HOME": str(home_two), "XDG_CONFIG_HOME": str(xdg_two), "ZDOTDIR": str(zdot_two),
                "ZIM_HOME": str(home_two / ".cache" / "zim"), "ZIM_ENV_HOME": str(home_two / ".cache" / "zim-env"),
                "ZIM_CONFIG_FILE": str(custom_zimrc), "ZIM_ENV_CONFIG": str(custom_zimenv), "ZIM_CONFIG_LINK": str(custom_registry),
                "ZIM_TEST_BUILD_LOG": str(temporary / "build-two.log"),
            })
            (temporary / "README.md").write_text(
                f"""# Isolated Zim consumer demo

This directory was rendered from `zim.opt.pb` with downloads/package work disabled.
`{controller}` is a local stub controller: it records cache builds and writes a harmless `init.zsh` comment.

- host deployment: `{payload}`
- canonical donor inputs: `{zimrc_d}` and `{zimenv_d}`
- user one config: `{local_root_one}`
- user two config: `{xdg_two / 'zsh'}` (custom outputs are under `{home_two / 'custom'}`)
- producer fixture: `{producer}`

Run tools without sourcing a live profile:

The wrappers clear inherited `ZIM_CONFIG_FILE`, `ZIM_ENV_CONFIG`, and
`ZIM_CONFIG_LINK` before setting their own demo values, and pin `TMPDIR` inside
this scratch root.

```bash
./user-one.sh {str(payload / 'bin' / 'status.sh')!r}
./user-one.sh {str(payload / 'bin' / 'config-user.sh')!r} --check zimrc
./user-one.sh {str(payload / 'bin' / 'config-inputs-user.sh')!r} status zimrc --json-array
./user-two.sh {str(payload / 'bin' / 'status.sh')!r}
```

`install-zim-donor.sh` changes the canonical donor and is intentionally not run by either wrapper's ordinary user setup.
All paths stay inside this demo root.
""",
                encoding="utf-8",
            )
            print(f"demo preserved at {temporary}")


if __name__ == "__main__":
    test_zim_consumer_lifecycle()
    print("ok: Zim consumer lifecycle")
