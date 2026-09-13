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


def render_host(payload: Path, scenario: Path, ansible_env: dict[str, str], default_context: str = "user") -> None:
    system = payload.parent / "system activation's root"
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
        "CONFIG_CONTEXTS": {
            "user": {
                "scope": "user", "root": "config", "subpath": "zsh", "install": "assemble", "dropins": "link",
                "configs": {
                    "zimrc": {"output": {"env": "ZIM_CONFIG_FILE", "default": "zimrc", "ignore": [str(payload / "etc" / "zimrc")]}},
                    "zimenv": {"output": {"env": "ZIM_ENV_CONFIG", "default": "zimenv", "ignore": [str(payload / "etc" / "zimenv")]}},
                },
            },
            "system": {
                "scope": "system", "root": str(system / "config"), "install": "assemble", "dropins": "copy",
                "configs": ["zimrc", "zimenv"],
            },
        },
        "ZIM_CONTEXT": default_context,
        "ZIM_CONTEXTS": {
            "user": {"config": "user"},
            "system": {
                "config": "system",
                "loader_root": str(system / "startup"),
                "zimrc_home": str(system / "cache" / "zim"),
                "zimenv_home": str(system / "cache" / "zimenv"),
                "registry": str(system / "registry" / "zimfw.conf"),
            },
        },
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


def extract_loader(
    block_in_file: Path,
    marker: str,
    startup: Path,
    destination: Path,
    *,
    cwd: Path,
    env: dict[str, str],
) -> Path:
    projected = run(
        [str(block_in_file), "--read", "-n", marker, str(startup)],
        cwd=cwd,
        env=env,
    )
    content = projected.stdout.encode()
    assert b"@@ZIM_" not in content
    destination.write_bytes(content)
    return destination


def source_loader(
    loader: Path,
    channel: str,
    environment: dict[str, str],
    build_log: Path,
    expected_home: Path,
    expected_config: Path,
    *,
    overrides: dict[str, str] | None = None,
) -> None:
    env = environment.copy()
    for name in ("ZIM_HOME", "ZIM_ENV_HOME", "ZIM_CONFIG_FILE", "ZIM_ENV_CONFIG", "COMPFUZOR_EMERGENCY"):
        env.pop(name, None)
    env.update(overrides or {})
    env["LOADER"] = str(loader)
    state = build_log.parent / f"{build_log.name}.{channel}.state"
    env["LOADER_STATE"] = str(state)
    expected_home.mkdir(parents=True, exist_ok=True)
    (expected_home / "init.zsh").unlink(missing_ok=True)
    build_log.write_text("", encoding="utf-8")
    if channel == "zimenv":
        script = 'source "$LOADER"; [[ -z ${ZIM_HOME+x} && -z ${ZIM_CONFIG_FILE+x} ]]'
    else:
        script = 'source "$LOADER"; print -r -- "$ZIM_HOME|$ZIM_CONFIG_FILE" > "$LOADER_STATE"'
    run(["zsh", "-dfc", script], cwd=loader.parent, env=env)
    assert (expected_home / "init.zsh").is_file()
    assert build_log.read_text(encoding="utf-8").splitlines() == [str(expected_config)]
    if channel == "zimrc":
        assert state.read_text(encoding="utf-8").strip() == f"{expected_home}|{expected_config}"


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

        deployed_sources = [path.relative_to(payload / "bin") for path in (payload / "bin").rglob("*") if path.is_file()]
        assert not [path for path in deployed_sources if path.suffix in {".ts", ".py"}]
        for bundle in ("config/command.mjs", "config-remote.mjs", "links/links.mjs", "zim/install.mjs"):
            content = (payload / "bin" / bundle).read_text(encoding="utf-8")
            assert content.startswith("#!/usr/bin/env")
            assert 'from "./' not in content
            assert not any(line.lstrip().startswith(("import ", "export ")) and ".ts" in line for line in content.splitlines())

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
        run([str(payload / "bin" / "config-assemble.sh"), "--context", "canonical"], cwd=payload, env=canonical_env)
        canonical_zimrc = payload / "etc" / "zimrc"
        canonical_zimenv = payload / "etc" / "zimenv"
        assert canonical_zimrc.is_file() and canonical_zimenv.is_file()

        # Relocate three loader inputs independently through v2 fields. The
        # runtime must consume this spec rather than derive sibling paths.
        zim_spec_path = payload / "etc" / "zim.spec.json"
        zim_spec = json.loads(zim_spec_path.read_text(encoding="utf-8"))
        canonical = zim_spec["canonical"]
        assert zim_spec["version"] == 2
        stale_spec = temporary / "zim-v1.spec.json"
        stale_spec.write_text(json.dumps(zim_spec | {"version": 1}), encoding="utf-8")
        stale_result = run(
            [
                str(payload / "bin" / "zim" / "install.mjs"), "status",
                "--spec", str(stale_spec),
                "--config-spec", str(payload / "etc" / "config.spec.json"),
                "--config-runner", str(payload / "bin" / "config" / "run.sh"),
            ],
            cwd=temporary,
            env=canonical_env,
            check=False,
        )
        assert stale_result.returncode == 2
        assert "unsupported Zim spec version: 1" in stale_result.stderr and "rerender" in stale_result.stderr
        assert set((
            "zimrcLegacy", "zimenvLegacy", "zimrcLoaderTemplate",
            "zimenvLoaderTemplate", "emergencyModule",
        )).issubset(canonical)
        relocated = temporary / "relocated loader sources"
        relocated.mkdir()
        relocated_zimenv_template = relocated / "zimenv loader's template.zsh"
        relocated_zimenv_template.write_bytes(
            (payload / "etc" / "zimenv.zsh").read_bytes()
            + b"# relocated-zimenv-template\n"
        )
        relocated_emergency = relocated / "emergency module's init.zsh"
        relocated_emergency.write_text(
            'print -r -- relocated-emergency > "$ZIM_TEST_EMERGENCY_LOG"\n',
            encoding="utf-8",
        )
        extra_zimrc_legacy = temporary / "retired canonical paths" / "zimrc"
        extra_zimenv_legacy = temporary / "retired canonical paths" / "zimenv"
        canonical["zimenvLoaderTemplate"] = str(relocated_zimenv_template)
        canonical["emergencyModule"] = str(relocated_emergency)
        canonical["zimrcLegacy"].append(str(extra_zimrc_legacy))
        canonical["zimenvLegacy"].append(str(extra_zimenv_legacy))
        zim_spec_path.write_text(json.dumps(zim_spec), encoding="utf-8")

        install_text = (payload / "bin" / "install.sh").read_text(encoding="utf-8")
        assert install_text.count('"$DIR/bin/install-zim.sh" "$@"') == 1
        assert "config-install.sh" not in install_text
        assert "install-zim-donor" not in install_text
        install_user = payload / "bin" / "install-user.sh"
        assert not install_user.exists() or "install-zim.sh" not in install_user.read_text(encoding="utf-8")
        assert (payload / "bin" / "install-zim.sh").is_file() and not (payload / "bin" / "install-zim.sh").is_symlink()
        for removed in (
            "install-zim-user.sh", "install-zimenv-loader-user.sh", "install-zimrc-loader-user.sh",
            "install-zim-caches-user.sh", "install-zim-registry-user.sh", "zimfw-channel.sh", "zim-registry.sh",
        ):
            assert not (payload / "bin" / removed).exists()
        assert (payload / "bin" / "install-zim-donor.sh").is_file()
        assert not any(path.is_symlink() and path.resolve() == payload / "bin" / "install-zim.sh" for path in (payload / "bin").iterdir())

        for command, summary in (
            (payload / "bin" / "install-zim.sh", "Install and activate Zim"),
            (payload / "bin" / "install-zim-context.sh", "Import a producer"),
            (payload / "bin" / "status-zim.sh", "Report Zim activation"),
        ):
            command_help = run([str(command), "--help"], cwd=temporary, env=canonical_env)
            assert summary in command_help.stdout, command_help.stdout

        # The same generated Zim surface uses bare install.sh regardless of
        # whether its runtime default is user or system.
        system_default_case = temporary / "system default case"
        system_default_case.mkdir()
        system_default_payload = system_default_case / "zim host"
        render_host(system_default_payload, system_default_case / "host.json", ansible_env, "system")
        install_system_text = (system_default_payload / "bin" / "install.sh").read_text(encoding="utf-8")
        assert install_system_text.count('"$DIR/bin/install-zim.sh" "$@"') == 1
        system_user_compositor = system_default_payload / "bin" / "install-user.sh"
        assert not system_user_compositor.exists() or "install-zim.sh" not in system_user_compositor.read_text(encoding="utf-8")
        for generated in ("install-zim.sh", "status-zim.sh", "zim/install.mjs"):
            assert (system_default_payload / "bin" / generated).is_file()
        assert not (system_default_payload / "bin" / "install-zim-system.sh").exists()

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
        for name in ("install-zim.sh", "config-install.sh", "status-zim.sh", "config-status.sh"):
            path = foreign / "bin" / name
            path.write_text(f'#!/bin/sh\necho {name} >> {str(foreign_log)!r}\nexit 0\n', encoding="utf-8")
            path.chmod(0o755)
        env_one["DIR"] = str(foreign)
        # Simulate values inherited from the pre-migration env/export contract.
        env_one["ZIM_CONFIG_FILE"] = str(canonical_zimrc)
        env_one["ZIM_ENV_CONFIG"] = str(canonical_zimenv)
        before_user = donor_digest(payload)
        local_root_one = xdg_one / "zsh"
        local_zimrc = local_root_one / "zimrc"
        local_zimenv = local_root_one / "zimenv"

        missing_config_bypass = run(
            [str(payload / "bin" / "install-zim.sh"), "--context", "user"],
            cwd=temporary,
            env=env_one | {
                "COMPFUZOR_CONFIG_BYPASS": "1",
                "COMPFUZOR_ZIM_INSTALL_STRATEGY": "stale-not-resolved",
            },
        )
        assert "required config outputs are unavailable" in missing_config_bypass.stderr
        assert not local_zimrc.exists() and not local_zimenv.exists()
        assert not (local_root_one / "zimfw.conf").exists()
        zim_bypass = run(
            [str(payload / "bin" / "install.sh")],
            cwd=temporary,
            env=env_one | {"COMPFUZOR_ZIM_BYPASS": "1", "COMPFUZOR_ZIM_CONTEXT": "undeclared-ignored"},
        )
        assert "skipped Zim install" in zim_bypass.stderr
        assert not local_zimrc.exists() and not build_log.exists()

        for path in (*zimrc_d.iterdir(), *zimenv_d.iterdir()):
            path.chmod(0o444)
        zimrc_d.chmod(0o555)
        zimenv_d.chmod(0o555)
        run([str(payload / "bin" / "install.sh")], cwd=temporary, env=env_one)
        assert not foreign_log.exists()

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

        bypass_extra = local_root_one / "zimrc.d" / "97-config-bypass.conf"
        bypass_extra.write_text("zmodule bypass-only\n", encoding="utf-8")
        output_before_bypass = local_zimrc.read_bytes()
        build_log.write_text("", encoding="utf-8")
        existing_config_bypass = run(
            [str(payload / "bin" / "install-zim.sh"), "--context", "user"],
            cwd=temporary,
            env=env_one | {
                "COMPFUZOR_CONFIG_BYPASS": "1",
                "COMPFUZOR_ZIM_INSTALL_STRATEGY": "stale-not-resolved",
            },
        )
        assert "skipped Zim config install" in existing_config_bypass.stderr
        assert local_zimrc.read_bytes() == output_before_bypass
        assert build_log.read_text(encoding="utf-8").splitlines() == [str(local_zimenv), str(local_zimrc)]
        bypass_extra.unlink()

        build_log.write_text("", encoding="utf-8")
        run([str(payload / "bin" / "install-zim.sh")], cwd=temporary, env=env_one | {"COMPFUZOR_ZIM_BYPASS": "true"})
        run([str(payload / "bin" / "install.sh")], cwd=temporary, env=env_one | {"COMPFUZOR_ZIM_BYPASS": "true"})
        assert build_log.read_text(encoding="utf-8") == ""
        visible_status = run([str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=env_one | {"COMPFUZOR_ZIM_BYPASS": "true"}, check=False)
        assert visible_status.returncode == 0

        user_loaders = {
            "zimenv": extract_loader(
                block_in_file,
                "zim-main-zimenv",
                zdot_one / ".zshenv",
                temporary / "projected-user-zimenv.zsh",
                cwd=temporary,
                env=env_one,
            ),
            "zimrc": extract_loader(
                block_in_file,
                "zim-main-zimrc",
                zdot_one / ".zshrc",
                temporary / "projected-user-zimrc.zsh",
                cwd=temporary,
                env=env_one,
            ),
        }
        assert b"@@ZIM_CACHE_HOME@@" in (payload / "etc" / "zimenv.zsh").read_bytes()
        assert b"relocated-zimenv-template" in user_loaders["zimenv"].read_bytes()
        assert str(local_zimenv).encode() in user_loaders["zimenv"].read_bytes()
        assert str(local_zimrc).encode() in user_loaders["zimrc"].read_bytes()

        emergency_log = temporary / "relocated-emergency.log"
        emergency_env = env_one.copy()
        for name in ("ZIM_HOME", "ZIM_ENV_HOME", "ZIM_CONFIG_FILE", "ZIM_ENV_CONFIG"):
            emergency_env.pop(name, None)
        emergency_env.update({
            "COMPFUZOR_EMERGENCY": "1",
            "ZIM_TEST_EMERGENCY_LOG": str(emergency_log),
        })
        run(["zsh", "-dfc", 'source "$1"', "emergency-loader", str(user_loaders["zimrc"])], cwd=temporary, env=emergency_env)
        assert emergency_log.read_text(encoding="utf-8").strip() == "relocated-emergency"

        # With all Zim selectors unset, projected loaders use the selected
        # context defaults. zimenv remains anonymous and leaks no ZIM globals.
        source_loader(user_loaders["zimenv"], "zimenv", env_one, build_log, home_one / ".cache" / "zim-env", local_zimenv)
        source_loader(user_loaders["zimrc"], "zimrc", env_one, build_log, home_one / ".cache" / "zim", local_zimrc)

        # Runtime channel overrides still win over embedded context defaults.
        override_root = temporary / "loader override's root"
        override_zimenv = override_root / "config" / "zimenv"
        override_zimrc = override_root / "config" / "zimrc"
        override_zimenv.parent.mkdir(parents=True)
        override_zimenv.write_text("# override zimenv\n", encoding="utf-8")
        override_zimrc.write_text("# override zimrc\n", encoding="utf-8")
        source_loader(
            user_loaders["zimenv"], "zimenv", env_one, build_log,
            override_root / "cache" / "zimenv", override_zimenv,
            overrides={"ZIM_ENV_HOME": str(override_root / "cache" / "zimenv"), "ZIM_ENV_CONFIG": str(override_zimenv)},
        )
        source_loader(
            user_loaders["zimrc"], "zimrc", env_one, build_log,
            override_root / "cache" / "zimrc", override_zimrc,
            overrides={"ZIM_HOME": str(override_root / "cache" / "zimrc"), "ZIM_CONFIG_FILE": str(override_zimrc)},
        )

        # Legacy canonical runtime values normalize to this activation's
        # resolved output, not to a hardcoded user path.
        source_loader(
            user_loaders["zimenv"], "zimenv", env_one, build_log,
            home_one / ".cache" / "zim-env", local_zimenv,
            overrides={"ZIM_ENV_CONFIG": str(canonical_zimenv)},
        )
        source_loader(
            user_loaders["zimrc"], "zimrc", env_one, build_log,
            home_one / ".cache" / "zim", local_zimrc,
            overrides={"ZIM_CONFIG_FILE": str(canonical_zimrc)},
        )

        producer = temporary / "producer"
        render_producer(producer, temporary / "producer-render.pb", ansible_env)
        producer_install = producer / "bin" / "install-zimfw.sh"
        assert producer_install.is_file()
        assert not (producer / "bin" / "install-user-zimfw.sh").exists()
        producer_compositor = (producer / "bin" / "install-user.sh").read_text(encoding="utf-8")
        assert producer_compositor.count('"$DIR/bin/install-zimfw.sh" "$@"') == 1

        skipped_import = run(
            [str(payload / "bin" / "install-zim-context.sh"), "--context", "user", str(producer)],
            cwd=temporary,
            env=env_one | {"COMPFUZOR_ZIM_BYPASS": "1"},
        )
        assert "skipped Zim import" in skipped_import.stderr
        assert not (local_root_one / "zimrc.d" / "55-producer-rc.conf").exists()

        run(
            [str(payload / "bin" / "config-inputs.sh"), "disable", "zimrc/zimrc", "20-environment.conf"],
            cwd=temporary,
            env=env_one,
        )
        build_log.write_text("", encoding="utf-8")
        producer_context_env = env_one | {"COMPFUZOR_ZIM_CONTEXT": "system"}
        run([str(producer_install), "--context", "user"], cwd=temporary, env=producer_context_env)
        assert build_log.read_text(encoding="utf-8").splitlines() == [str(local_zimenv), str(local_zimrc)]
        producer_rc = local_root_one / "zimrc.d" / "55-producer-rc.conf"
        producer_env_disabled = local_root_one / "zimenv.d" / "55-producer-env.conf.disabled"
        assert producer_rc.is_symlink()
        assert producer_env_disabled.is_symlink()
        assert not (local_root_one / "zimenv.d" / "55-producer-env.conf").exists()
        assert (local_root_one / "zimrc.d" / "20-environment.conf.disabled").exists()
        assert donor_digest(payload) == before_user

        run(
            [str(payload / "bin" / "config-inputs.sh"), "enable", "zimenv/zimenv", "55-producer-env.conf"],
            cwd=temporary,
            env=env_one,
        )
        build_log.write_text("", encoding="utf-8")
        run([str(producer_install)], cwd=temporary, env=env_one)
        assert (local_root_one / "zimenv.d" / "55-producer-env.conf").is_symlink()
        assert not producer_env_disabled.exists()
        assert build_log.read_text(encoding="utf-8").splitlines() == [str(local_zimenv), str(local_zimrc)]

        run([str(payload / "bin" / "config-sync-inputs.sh"), "--strategy", "copy", "zimrc"], cwd=temporary, env=env_one)
        assert not (local_root_one / "zimrc.d" / "20-environment.conf.disabled").is_symlink()
        assert producer_rc.is_symlink()

        run([str(payload / "bin" / "config-publish.sh"), "--strategy", "copy", "zimrc"], cwd=temporary, env=env_one)
        assert local_zimrc.is_file() and not local_zimrc.is_symlink()
        assert local_zimrc.read_bytes() == canonical_zimrc.read_bytes()
        run([str(payload / "bin" / "config-publish.sh"), "--strategy", "link", "zimrc"], cwd=temporary, env=env_one)
        assert local_zimrc.is_symlink() and local_zimrc.resolve() == canonical_zimrc
        run([str(payload / "bin" / "config-assemble.sh"), "zimrc"], cwd=temporary, env=env_one)
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
        install_two = run([str(payload / "bin" / "install.sh")], cwd=temporary, env=env_two)
        assert custom_zimrc.is_file() and custom_zimenv.is_file()
        assert custom_registry.is_symlink() and custom_registry.resolve() == canonical_zimrc, (install_two.stdout, install_two.stderr, list(home_two.rglob("zimfw.conf")), list(xdg_two.rglob("zimfw.conf")))
        assert not (xdg_two / "zsh" / "zimrc.d" / producer_rc.name).exists()
        assert donor_digest(payload) == before_user

        # One implementation targets a genuinely non-user activation context.
        system_root = temporary / "system activation's root"
        system_build_log = temporary / "build-system.log"
        system_env = user_env(temporary / "irrelevant system home", temporary / "irrelevant system xdg", temporary / "irrelevant system zdot", payload, system_build_log, block_in_file)
        sudo_shim = temporary / "sudo-shim"
        sudo_shim.mkdir()
        sudo_log = temporary / "sudo.log"
        (sudo_shim / "sudo").write_text(f'#!/bin/sh\necho called >> {str(sudo_log)!r}\nexit 99\n', encoding="utf-8")
        (sudo_shim / "sudo").chmod(0o755)
        system_env["PATH"] = os.pathsep.join((str(sudo_shim), system_env["PATH"]))
        system_env.update({
            "COMPFUZOR_ZIM_CONTEXT": "system",
            # Compatibility names remain runtime inputs to the Zim dispatcher.
            "COMPFUZOR_CONFIG_INSTALL_STRATEGY": "copy",
            "COMPFUZOR_CONFIG_DROPINS_STRATEGY": "link",
        })
        run([str(payload / "bin" / "install-zim.sh")], cwd=temporary, env=system_env)
        assert (system_root / "config" / "zimrc").is_file()
        assert not (system_root / "config" / "zimrc.d").exists()

        # Command aliases are user-created only. Alias context beats env; flags
        # beat both alias and environment strategy settings.
        system_alias = payload / "bin" / "install-zim-system.sh"
        system_alias.symlink_to("install-zim.sh")
        alias_env = system_env | {
            "COMPFUZOR_ZIM_CONTEXT": "user",
            "COMPFUZOR_ZIM_INSTALL_STRATEGY": "copy",
            "COMPFUZOR_ZIM_DROPINS_STRATEGY": "link",
        }
        run([str(system_alias), "--install", "assemble", "--dropins", "copy"], cwd=temporary, env=alias_env)
        assert (system_root / "config" / "zimrc.d" / "20-environment.conf").is_file()
        assert not (system_root / "config" / "zimrc.d" / "20-environment.conf").is_symlink()
        assert (system_root / "startup" / ".zshenv").is_file()
        assert (system_root / "startup" / ".zshrc").is_file()
        assert (system_root / "cache" / "zimenv" / "init.zsh").is_file()
        assert (system_root / "cache" / "zim" / "init.zsh").is_file()
        assert (system_root / "registry" / "zimfw.conf").is_symlink()
        assert (system_root / "registry" / "zimfw.conf").resolve() == canonical_zimrc
        assert not sudo_log.exists()

        system_loaders = {
            "zimenv": extract_loader(
                block_in_file,
                "zim-main-zimenv",
                system_root / "startup" / ".zshenv",
                temporary / "projected-system-zimenv.zsh",
                cwd=temporary,
                env=system_env,
            ),
            "zimrc": extract_loader(
                block_in_file,
                "zim-main-zimrc",
                system_root / "startup" / ".zshrc",
                temporary / "projected-system-zimrc.zsh",
                cwd=temporary,
                env=system_env,
            ),
        }
        # The apostrophe-bearing system paths exercise Zsh literal quoting.
        # No external ZIM selector is needed to load the selected activation.
        source_loader(
            system_loaders["zimenv"], "zimenv", system_env, system_build_log,
            system_root / "cache" / "zimenv", system_root / "config" / "zimenv",
        )
        source_loader(
            system_loaders["zimrc"], "zimrc", system_env, system_build_log,
            system_root / "cache" / "zim", system_root / "config" / "zimrc",
        )

        system_override = temporary / "system runtime override"
        system_override_zimenv = system_override / "config" / "zimenv"
        system_override_zimrc = system_override / "config" / "zimrc"
        system_override_zimenv.parent.mkdir(parents=True)
        system_override_zimenv.write_text("# system override zimenv\n", encoding="utf-8")
        system_override_zimrc.write_text("# system override zimrc\n", encoding="utf-8")
        source_loader(
            system_loaders["zimenv"], "zimenv", system_env, system_build_log,
            system_override / "cache" / "zimenv", system_override_zimenv,
            overrides={
                "ZIM_ENV_HOME": str(system_override / "cache" / "zimenv"),
                "ZIM_ENV_CONFIG": str(system_override_zimenv),
            },
        )
        source_loader(
            system_loaders["zimrc"], "zimrc", system_env, system_build_log,
            system_override / "cache" / "zimrc", system_override_zimrc,
            overrides={
                "ZIM_HOME": str(system_override / "cache" / "zimrc"),
                "ZIM_CONFIG_FILE": str(system_override_zimrc),
            },
        )

        # Canonical residue falls back to the system activation's embedded
        # config outputs, then leaves that activation clean for status.
        source_loader(
            system_loaders["zimenv"], "zimenv", system_env, system_build_log,
            system_root / "cache" / "zimenv", system_root / "config" / "zimenv",
            overrides={"ZIM_ENV_CONFIG": str(extra_zimenv_legacy)},
        )
        source_loader(
            system_loaders["zimrc"], "zimrc", system_env, system_build_log,
            system_root / "cache" / "zim", system_root / "config" / "zimrc",
            overrides={"ZIM_CONFIG_FILE": str(extra_zimrc_legacy)},
        )
        system_status = run([str(payload / "bin" / "status-zim.sh"), "--context", "system"], cwd=temporary, env=system_env, check=False)
        assert system_status.returncode == 0, (system_status.stdout, system_status.stderr)

        system_build_log.write_text("", encoding="utf-8")
        explicit_user_env = env_one | {"COMPFUZOR_ZIM_CONTEXT": "system", "ZIM_TEST_BUILD_LOG": str(system_build_log)}
        run([str(system_alias), "--context", "user", "--install", "copy"], cwd=temporary, env=explicit_user_env)
        assert all(str(local_root_one) in path for path in system_build_log.read_text(encoding="utf-8").splitlines())

        unknown_alias = payload / "bin" / "install-zim-unknown.sh"
        unknown_alias.symlink_to("install-zim.sh")
        unknown = run([str(unknown_alias)], cwd=temporary, env=system_env, check=False)
        assert unknown.returncode == 2 and "undeclared context" in unknown.stderr
        run([str(unknown_alias), "--context", "user", "--install", "copy"], cwd=temporary, env=env_one)
        unknown_alias.unlink()

        unsupported_alias = payload / "bin" / "my-zim-installer"
        unsupported_alias.symlink_to("install-zim.sh")
        unsupported = run([str(unsupported_alias)], cwd=temporary, env=env_one, check=False)
        assert unsupported.returncode == 2 and "unsupported Zim command alias" in unsupported.stderr
        run([str(unsupported_alias), "--context", "user", "--install", "copy"], cwd=temporary, env=env_one)
        unsupported_alias.unlink()

        # Changing only the compiled default changes direct behavior; the Zim
        # public executable set is unchanged.
        zim_spec_path = payload / "etc" / "zim.spec.json"
        zim_spec = json.loads(zim_spec_path.read_text(encoding="utf-8"))
        original_default = zim_spec["defaultContext"]
        zim_spec["defaultContext"] = "system"
        zim_spec_path.write_text(json.dumps(zim_spec), encoding="utf-8")
        default_env = system_env.copy()
        for key in (
            "COMPFUZOR_ZIM_CONTEXT", "COMPFUZOR_ZIM_INSTALL_STRATEGY", "COMPFUZOR_ZIM_DROPINS_STRATEGY",
            "COMPFUZOR_CONFIG_INSTALL_STRATEGY", "COMPFUZOR_CONFIG_DROPINS_STRATEGY",
        ):
            default_env.pop(key, None)
        system_build_log.write_text("", encoding="utf-8")
        run([str(payload / "bin" / "install-zim.sh"), "--install", "copy"], cwd=temporary, env=default_env)
        assert all(str(system_root / "config") in path for path in system_build_log.read_text(encoding="utf-8").splitlines())
        zim_spec["defaultContext"] = original_default
        zim_spec_path.write_text(json.dumps(zim_spec), encoding="utf-8")

        run([str(payload / "bin" / "install-zim.sh"), "--context", "user"], cwd=temporary, env=env_one)
        direct_complete_status = run([str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=env_one, check=False)
        assert direct_complete_status.returncode == 0
        assert direct_complete_status.stdout.count("assembly\tready\tzimenv\tzimenv") == 1
        assert direct_complete_status.stdout.count("assembly\tready\tzimrc\tzimrc") == 1
        for channel in ("zimenv", "zimrc"):
            assert f"zim {channel} loader: ok:" in direct_complete_status.stdout
            assert f"zim {channel} cache: ok:" in direct_complete_status.stdout
        activation_only_status = run(
            [str(payload / "bin" / "status-zim.sh"), "--activation-only"],
            cwd=temporary,
            env=env_one,
            check=False,
        )
        assert activation_only_status.returncode == 0
        assert "assembly\tready\t" not in activation_only_status.stdout
        clean_status = run([str(payload / "bin" / "status.sh")], cwd=temporary, env=env_one, check=False)
        assert clean_status.returncode == 0, (clean_status.stdout, clean_status.stderr)
        assert clean_status.stdout.count("assembly\tready\tzimenv\tzimenv") == 1
        assert clean_status.stdout.count("assembly\tready\tzimrc\tzimrc") == 1
        assert not foreign_log.exists()

        # Direct Zim status covers the generic selected-context config health,
        # preserves evaluation-error exit 2, and aggregate status treats that
        # error as attention rather than historical not-applicable.
        broken_config = local_root_one / "zimrc.d" / "98-status-error.conf"
        broken_config.write_text("'unterminated\n", encoding="utf-8")
        direct_config_error = run(
            [str(payload / "bin" / "status-zim.sh"), "--context", "user"],
            cwd=temporary,
            env=env_one | {
                "COMPFUZOR_ZIM_INSTALL_STRATEGY": "stale-ignored-by-status",
                "COMPFUZOR_ZIM_DROPINS_STRATEGY": "stale-ignored-by-status",
            },
            check=False,
        )
        assert direct_config_error.returncode == 2
        assert "candidate validation failed" in direct_config_error.stdout
        assert direct_config_error.stdout.count("assembly\tevaluation-error\tzimrc\tzimrc") == 1
        aggregate_config_error = run([str(payload / "bin" / "status.sh")], cwd=temporary, env=env_one, check=False)
        assert aggregate_config_error.returncode == 1
        assert aggregate_config_error.stdout.count("assembly\tevaluation-error\tzimrc\tzimrc") == 1
        broken_config.unlink()

        different = temporary / "different-loader.zsh"
        different.write_text("echo different\n", encoding="utf-8")
        run(
            [str(block_in_file), "-n", "zim-main-zimrc", "-i", str(different), "-o", str(zdot_one / ".zshrc")],
            cwd=temporary,
            env=env_one,
        )
        changed_loader = run([str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=env_one, check=False)
        assert changed_loader.returncode == 1 and "differs" in changed_loader.stdout
        run([str(payload / "bin" / "install-zim.sh"), "--context", "user"], cwd=temporary, env=env_one)

        loader_template = payload / "etc" / "zimrc.zsh"
        loader_backup = loader_template.read_bytes()
        loader_template.unlink()
        missing_loader = run([str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=env_one, check=False)
        assert missing_loader.returncode == 1 and "loader template is missing or invalid" in missing_loader.stdout
        loader_template.write_bytes(loader_backup)

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
            write_environment_wrapper(temporary / "system.sh", common | {
                "HOME": str(temporary / "irrelevant system home"),
                "XDG_CONFIG_HOME": str(temporary / "irrelevant system xdg"),
                "ZDOTDIR": str(temporary / "irrelevant system zdot"),
                "ZIM_TEST_BUILD_LOG": str(system_build_log),
                "COMPFUZOR_ZIM_CONTEXT": "system",
            })
            hostile_env = os.environ.copy()
            hostile_env.update({
                "ZIM_CONFIG_FILE": "/hostile/zimrc",
                "ZIM_ENV_CONFIG": "/hostile/zimenv",
                "ZIM_CONFIG_LINK": "/hostile/registry",
                "COMPFUZOR_ZIM_CONTEXT": "undeclared",
                "COMPFUZOR_ZIM_INSTALL_STRATEGY": "invalid",
                "COMPFUZOR_ZIM_DROPINS_STRATEGY": "invalid",
                "COMPFUZOR_CONFIG_INSTALL_STRATEGY": "invalid",
                "COMPFUZOR_CONFIG_DROPINS_STRATEGY": "invalid",
            })
            run([str(temporary / "user-one.sh"), str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=hostile_env)
            run([str(temporary / "system.sh"), str(payload / "bin" / "status-zim.sh")], cwd=temporary, env=hostile_env)
            (temporary / "README.md").write_text(
                f"""# Isolated Zim consumer demo

This directory was rendered from `zim.opt.pb` with downloads/package work disabled.
`{controller}` is a local stub controller: it records cache builds and writes a harmless `init.zsh` comment.

- host deployment: `{payload}`
- canonical donor inputs: `{zimrc_d}` and `{zimenv_d}`
- user one config: `{local_root_one}`
- user two config: `{xdg_two / 'zsh'}` (custom outputs are under `{home_two / 'custom'}`)
- explicit system activation: `{system_root}`
- producer fixture: `{producer}` (`bin/install-zimfw.sh`, explicitly user-scoped)

Run tools without sourcing a live profile:

The wrappers clear inherited Zim context, strategy, output, registry, and config
bypass variables before setting their own demo values, and pin `TMPDIR` inside
this scratch root. `install-zim-system.sh` under the host `bin/` is a
user-created symlink retained by the test; the playbook did not generate it.
The fixture also relocates one v2 loader template, the emergency module, and
extra legacy config names through `zim.spec.json` to prove those fields are read.

```bash
./user-one.sh {str(payload / 'bin' / 'status.sh')!r}
./user-one.sh {str(payload / 'bin' / 'config-assemble.sh')!r} --check zimrc
./user-one.sh {str(payload / 'bin' / 'config-inputs.sh')!r} status zimrc --json-array
./user-two.sh {str(payload / 'bin' / 'status.sh')!r}
./system.sh {str(payload / 'bin' / 'status-zim.sh')!r}
./system.sh {str(payload / 'bin' / 'install-zim-system.sh')!r} --install assemble --dropins copy
```

`install-zim-donor.sh` changes the canonical donor and is intentionally not run by these ordinary context wrappers.
All paths stay inside this demo root.
""",
                encoding="utf-8",
            )
            print(f"demo preserved at {temporary}")


if __name__ == "__main__":
    test_zim_consumer_lifecycle()
    print("ok: Zim consumer lifecycle")
