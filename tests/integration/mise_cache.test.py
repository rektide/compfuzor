#!/usr/bin/env python3
"""Exercise the rendered mise-cache.ts cache inventory/gc/clear bin."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "mise-cache-test"
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
        env = {
            "HOME": str(home),
            "XDG_CACHE_HOME": str(xdg_cache),
            "MISE_DATA_DIR": str(data),
            # node for the bin itself; the stubs shadow the catalog tools
            "PATH": f"{shims}:{Path(NODE).parent}:/usr/bin:/bin",
            "RUSTUP_HOME": "",
            "CARGO_HOME": "",
        }

        listed = run([str(cache_bin), "list"], cwd=temporary, env=env)
        for name in ("npm", "gradle", "pip", "pnpm", "mise-downloads", "mise-installs"):
            assert f"{name:<14} present" in listed.stdout, listed.stdout
        assert "visibility only" in listed.stdout

        fast = run([str(cache_bin), "status", "--fast"], cwd=temporary, env=env)
        assert "cache areas: 6 present" in fast.stdout, fast.stdout
        assert str(home / ".gradle" / "caches") in fast.stdout
        assert "TOTAL" not in fast.stdout  # --fast skips du

        full = run([str(cache_bin), "status"], cwd=temporary, env=env)
        assert "TOTAL" in full.stdout, full.stdout
        # expand areas break installs down per tool
        assert "node" in full.stdout and "rust" in full.stdout

        # aggregate status runs the reporter with its fixed args
        aggregate = run([str(bin_dir / "status.sh"), "--fast"], cwd=temporary, env=env, check=False)
        assert "=== mise-cache.ts ===" in aggregate.stdout, aggregate.stdout

        gc = run([str(cache_bin), "gc", "--all", "--dry-run"], cwd=temporary, env=env)
        assert "[dry-run] mise prune --tools" in gc.stdout, gc.stdout

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


if __name__ == "__main__":
    test_mise_cache_bin()
    print("ok: mise cache bin")
