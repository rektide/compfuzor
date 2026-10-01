#!/usr/bin/env python3
"""Exercise the rendered mise-cache.ts cache inventory/gc/clear bin."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "mise-cache"
NODE = subprocess.run(["node", "-p", "process.execPath"], check=True, text=True, capture_output=True).stdout.strip()


def run(command: list[str], *, cwd: Path, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(f"command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def render(playbook: str, payload: Path, type_: str, name: str) -> None:
    payload.mkdir(parents=True, exist_ok=True)
    scenario = payload.parent / f"scenario-{name}.json"
    scenario.write_text(json.dumps({
        "TYPE": type_,
        "NAME": name,
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
        ["ansible-playbook", "-i", "localhost,", "-c", "local", str(ROOT / playbook), "-e", f"@{scenario}"],
        cwd=ROOT,
        env=ansible_env,
    )


def test_mise_cache_bin() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mise cache-", dir=SCRATCH) as tmp:
        temporary = Path(tmp)
        payload = temporary / "deploy"
        render("mise.opt.pb", payload, "mise", "mise-main")

        bin_dir = payload / "bin"
        cache_bin = bin_dir / "mise-cache.ts"
        assert cache_bin.is_file()
        assert not (bin_dir / "mise-cache.sh").exists()  # bash precursor retired
        rendered = cache_bin.read_text(encoding="utf-8")
        assert rendered.startswith("#!/usr/bin/env node")
        assert "MISE2_CONFIG_DEFAULT: string | null = null" in rendered  # plain mise render
        # aggregate status.sh bakes the reporter with its fixed --fast arg
        assert "mise-cache.ts" in (bin_dir / "status.sh").read_text(encoding="utf-8")

        home = temporary / "home"
        xdg_cache = temporary / "xdg" / "cache"
        data = temporary / "data" / "mise"
        for area in (
            home / ".npm",
            home / ".gradle" / "caches",
            xdg_cache / "pip",
            xdg_cache / "pnpm",
            data / "downloads",
            data / "installs" / "node",
            data / "installs" / "rust",
        ):
            area.mkdir(parents=True)
            (area / "payload").write_bytes(os.urandom(4096))
        # Executable failing stubs shadow the real tools: command -v reports
        # them, every catalog query returns empty (so the fallback applies),
        # and no real tool runs -- npm would otherwise create ~/.npm and
        # ~/.config as a side effect of being queried.
        shims = temporary / "shims"
        shims.mkdir()
        for tool in ("mise", "npm", "pnpm", "go", "deno", "bun", "uv", "pip", "dotnet", "yarn"):
            stub = shims / tool
            stub.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            stub.chmod(0o755)
        # mise becomes a dispatcher: a fixed installed-tool map for `ls`
        # (detection input) and an XDG-relative answer for `cache path`.
        (shims / "mise").write_text(
            "#!/bin/sh\n"
            'printf "mise %s\\n" "$*" >> "$TOOL_LOG"\n'
            '[ "$DISCOVERY_FAIL" = 1 ] && exit 1\n'
            '[ "$DISCOVERY_FAIL" = malformed ] && { printf "not-json\\n"; exit 0; }\n'
            'case "$1" in\n'
            '  ls) if [ "$2" = "--prunable" ]; then printf \'{"rust":[{"version":"1.80.0"}]}\\n\'; else printf \'{"bun":[{"version":"1.0.0"}],"go":[{"version":"1.26.0"}]}\\n\'; fi ;;\n'
            '  cache) [ "$2" = "path" ] && printf \'%s/mise\\n\' "$XDG_CACHE_HOME" ;;\n'
            "esac\n",
            encoding="utf-8",
        )
        env = {
            "HOME": str(home),
            "XDG_CACHE_HOME": str(xdg_cache),
            "MISE_DATA_DIR": str(data),
            # node for the bin itself; the stubs shadow the catalog tools
            "PATH": f"{shims}:{Path(NODE).parent}:/usr/bin:/bin",
            "RUSTUP_HOME": "",
            "CARGO_HOME": "",
            "TOOL_LOG": str(temporary / "tool.log"),
        }

        listed = run([str(cache_bin), "list"], cwd=temporary, env=env)
        for name in ("npm", "gradle", "pip", "pnpm", "mise-downloads", "mise-installs"):
            assert f"{name:<14} present" in listed.stdout, listed.stdout
        assert "visibility only" in listed.stdout

        fast = run([str(cache_bin), "status", "--fast"], cwd=temporary, env=env)
        assert "cache areas: 7 present" in fast.stdout, fast.stdout
        assert str(home / ".gradle" / "caches") in fast.stdout
        assert "TOTAL" not in fast.stdout  # --fast skips du

        full = run([str(cache_bin), "status"], cwd=temporary, env=env)
        assert "TOTAL" in full.stdout, full.stdout
        assert "rust@1.80.0" in full.stdout, full.stdout
        # expand areas break installs down per tool
        assert "node" in full.stdout and "rust" in full.stdout

        # aggregate status runs the reporter with its fixed args
        aggregate = run([str(bin_dir / "status.sh"), "--fast"], cwd=temporary, env=env, check=False)
        assert "=== mise-cache.ts ===" in aggregate.stdout, aggregate.stdout

        gc = run([str(cache_bin), "gc", "--all", "--dry-run"], cwd=temporary, env=env)
        assert "mise prune --tools" not in gc.stdout, gc.stdout
        assert "[dry-run] pnpm store prune" in gc.stdout, gc.stdout

        dry = run([str(cache_bin), "clear", "gradle", "pnpm", "--dry-run"], cwd=temporary, env=env)
        assert f"[dry-run] rm -rf {home / '.gradle' / 'caches'}" in dry.stdout, dry.stdout
        assert f"[dry-run] rm -rf {xdg_cache / 'pnpm'}" in dry.stdout, dry.stdout
        assert (home / ".gradle" / "caches").exists()

        visibility = run([str(cache_bin), "clear", "mise-installs"], cwd=temporary, env=env)
        assert "no clear action" in visibility.stdout, visibility.stdout
        assert (data / "installs").exists()

        unknown = run([str(cache_bin), "clear", "bogus"], cwd=temporary, env=env, check=False)
        assert unknown.returncode == 2 and "unknown area: bogus" in unknown.stderr

        cleared = run([str(cache_bin), "clear", "gradle"], cwd=temporary, env=env)
        assert f"rm -rf {home / '.gradle' / 'caches'}" in cleared.stdout, cleared.stdout
        assert not (home / ".gradle" / "caches").exists()
        # unselected areas untouched
        assert (home / ".npm").exists()

        # Native clear availability must not execute bare tools, including
        # during dry-run. Query calls remain allowed and get logged explicitly.
        (shims / "npm").write_text(
            '#!/bin/sh\nprintf "npm %s\\n" "$*" >> "$TOOL_LOG"\nexit 1\n',
            encoding="utf-8",
        )
        tool_log = Path(env["TOOL_LOG"])
        tool_log.write_text("")
        native_dry = run([str(cache_bin), "clear", "npm", "--dry-run"], cwd=temporary, env=env)
        assert "[dry-run] npm cache clean --force" in native_dry.stdout
        assert sorted(tool_log.read_text().splitlines()) == ["mise cache path", "npm config get cache"], tool_log.read_text()
        assert (home / ".npm").exists()

        # Deterministic allocation stub: Rust's two toolchain leaves share
        # one physical root via a symlink and must contribute only once.
        rust_root = data / "installs" / "rust"
        rustup = home / ".rustup"
        rustup.mkdir()
        (rustup / "toolchains").symlink_to(rust_root, target_is_directory=True)
        for path in (home / ".cargo" / "registry", home / ".cargo" / "git", rustup / "downloads"):
            path.mkdir(parents=True)
        du_stub = shims / "du"
        du_stub.write_text(
            '#!/bin/sh\n[ "$DU_FAIL" = 1 ] && exit 1\nshift 2\n'
            'for path do\ncase "${path##*/}" in registry) kb=12;; git) kb=8;; rust) kb=20;; *) kb=4;; esac\n'
            'printf "%s\\t%s\\n" "$kb" "$path"\ndone\n', encoding="utf-8",
        )
        du_stub.chmod(0o755)
        grouped = run([str(cache_bin), "status"], cwd=temporary, env=env)
        assert f'{"Rust":<14} {"44.0K":>9}  topic total' in grouped.stdout, grouped.stdout
        assert f'{"  toolchains":<14} {"20.0K":>9}  Rust subtotal' in grouped.stdout, grouped.stdout
        assert f'{"  libraries":<14} {"20.0K":>9}  Rust subtotal' in grouped.stdout, grouped.stdout
        assert f'{"  ancillary":<14} {"4.0K":>9}  Rust subtotal' in grouped.stdout, grouped.stdout
        assert "registry" in grouped.stdout and "git" in grouped.stdout
        assert "Node" in grouped.stdout
        assert f'{"Node":<14} {"8.0K":>9}  topic total' in grouped.stdout, grouped.stdout
        assert f'{"TOTAL":<14} {"44.0K":>9}' in grouped.stdout, grouped.stdout
        (home / "go" / "pkg" / "mod").mkdir(parents=True)
        (xdg_cache / "go-build").mkdir()
        go_grouped = run([str(cache_bin), "status"], cwd=temporary, env=env)
        assert f'{"Go":<14} {"8.0K":>9}  topic total' in go_grouped.stdout, go_grouped.stdout
        failed_du = run([str(cache_bin), "status"], cwd=temporary, env={**env, "DU_FAIL": "1"})
        assert f'{"Rust":<14} {"unknown":>9}  topic total' in failed_du.stdout, failed_du.stdout
        failed_prunable = run([str(cache_bin), "status", "--fast"], cwd=temporary, env={**env, "DISCOVERY_FAIL": "1"})
        assert "unavailable:" in failed_prunable.stdout and "  none" not in failed_prunable.stdout
        du_stub.unlink()

        # Exact overrides: an explicit state root must not acquire /mise;
        # installs override outranks data, and XDG data is the default parent.
        state = temporary / "state-override"
        installs = temporary / "installs-override"
        state.mkdir()
        installs.mkdir()
        override_env = {**env, "MISE_STATE_DIR": str(state), "MISE_INSTALLS_DIR": str(installs)}
        override = run([str(cache_bin), "list"], cwd=temporary, env=override_env)
        assert f'{"mise-state":<14} present' in override.stdout, override.stdout
        assert f'{"mise-installs":<14} present' in override.stdout, override.stdout
        override_status = run([str(cache_bin), "status", "--fast"], cwd=temporary, env=override_env)
        assert str(state) in override_status.stdout and str(state / "mise") not in override_status.stdout
        assert str(installs) in override_status.stdout
        xdg_data = temporary / "xdg-data"
        (xdg_data / "mise" / "installs").mkdir(parents=True)
        xdg_env = {**env, "MISE_DATA_DIR": "", "XDG_DATA_HOME": str(xdg_data)}
        xdg_status = run([str(cache_bin), "status", "--fast"], cwd=temporary, env=xdg_env)
        assert str(xdg_data / "mise" / "installs") in xdg_status.stdout

        # config lane: config-mise-cache.ts composes into config.sh and
        # stages the detected catalog (base + areas mapped from the fake
        # mise tool list: bun, go)
        config_bin = bin_dir / "config-mise-cache.ts"
        assert config_bin.is_file()
        assert "config-mise-cache.ts" in (bin_dir / "config.sh").read_text(encoding="utf-8")
        staged = run([str(config_bin)], cwd=temporary, env=env)
        assert "staged" in staged.stdout and "2 mise tools" in staged.stdout, staged.stdout
        assert (payload / "etc" / "mise-cache.areas.json").is_file()
        catalog_path = payload / "etc" / "mise-cache.areas.json"
        saved = catalog_path.read_bytes()
        for failure in ("1", "malformed"):
            failed = run([str(config_bin)], cwd=temporary, env={**env, "DISCOVERY_FAIL": failure}, check=False)
            assert failed.returncode == 1 and "catalog unchanged" in failed.stderr, failed.stderr
            assert catalog_path.read_bytes() == saved

        detected = run([str(cache_bin), "list"], cwd=temporary, env=env)
        assert "catalog: computed" in detected.stdout, detected.stdout
        for name in ("bun", "go-mod", "go-build"):  # mapped from fake mise ls
            assert f"{name:<14} present" in detected.stdout or f"{name:<14} absent" in detected.stdout
        assert "npm" not in detected.stdout  # node not in the fake tool list
        assert "pnpm" not in detected.stdout
        # detection gates gc selection too: pnpm has no gc offer anymore
        detected_gc = run([str(cache_bin), "gc", "--all", "--dry-run"], cwd=temporary, env=env, check=False)
        assert detected_gc.returncode == 2
        assert "mise prune --tools" not in detected_gc.stdout, detected_gc.stdout
        assert "pnpm store prune" not in detected_gc.stdout

        # staged catalog removed -> rendered fallback returns
        (payload / "etc" / "mise-cache.areas.json").unlink()
        fallback = run([str(cache_bin), "list"], cwd=temporary, env=env)
        assert "rendered fallback" in fallback.stdout and "npm" in fallback.stdout

        empty = temporary / "empty-home"
        empty.mkdir()
        env["HOME"] = str(empty)
        env.pop("XDG_CACHE_HOME")
        env.pop("MISE_DATA_DIR")
        bare = run([str(cache_bin), "status", "--fast"], cwd=temporary, env=env, check=False)
        assert bare.returncode == 2 and "no cache areas present" in bare.stdout

        # mise2 render routes mise through its isolated config root
        payload2 = temporary / "deploy2"
        render("mise2.opt.pb", payload2, "mise2", "mise2-main")
        text = (payload2 / "bin" / "mise-cache.ts").read_text(encoding="utf-8")
        assert 'MISE2_CONFIG_DEFAULT = "' in text
        assert "MISE2_CONFIG_DEFAULT" in (payload2 / "bin" / "config-mise-cache.ts").read_text(encoding="utf-8")
        # Leave rendered files only when requested, for a separate tsgo pass.
        if os.environ.get("MISE_CACHE_RENDER_DIR"):
            import shutil
            destination = Path(os.environ["MISE_CACHE_RENDER_DIR"])
            for name, source in (("mise", payload), ("mise2", payload2)):
                (destination / name).mkdir(parents=True, exist_ok=True)
                for filename in ("mise-cache.ts", "config-mise-cache.ts"):
                    shutil.copyfile(source / "bin" / filename, destination / name / filename)


if __name__ == "__main__":
    test_mise_cache_bin()
    print("ok: mise cache bin")
