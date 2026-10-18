#!/usr/bin/env python3
"""Render the real Playwright playbooks without installing or launching browsers."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / ".test-agent" / "playwright"


def render(playbook: str, directory: Path, **extra: object) -> Path:
    deployment = directory / "deployment"
    variables = {
        "DIR": str(deployment),
        "ETCS_DIR": str(directory / "etc"),
        "VARS_DIR": str(directory / "var"),
        "CACHES_DIR": str(directory / "cache"),
        "LOGS_DIR": str(directory / "log"),
        "SHARES_DIR": str(directory / "share"),
        "REPO_BYPASS": True,
        "PKGS_BYPASS": True,
        "APT_BYPASS": True,
        "MODULES_BYPASS": True,
        "SYSTEMD_INSTALL_BYPASS": True,
        "SYSTEMD_THUNK_BYPASS": True,
        "BINS_RUN_BYPASS": True,
        "GLOBAL_BINS_BYPASS": True,
        **extra,
    }
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", "-c", "local", playbook,
         "-e", json.dumps(variables)],
        cwd=ROOT,
        env=os.environ | {"ANSIBLE_CONFIG": str(ROOT / "ansible.cfg")},
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"{result.stdout}\n{result.stderr}"
    for script in (deployment / "bin").glob("*.sh"):
        subprocess.run(["bash", "-n", str(script)], check=True)
    return deployment


def test_playwright_mcp() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="render-mcp-", dir=SCRATCH) as tmp:
        directory = Path(tmp)
        deployment = render("playwright-mcp.src.pb", directory)
        record = json.loads((deployment / "etc/mcp.json").read_text())
        config = json.loads((deployment / "etc/playwright.json").read_text())
        display = record.pop("environment")
        assert set(display) <= {"DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XAUTHORITY"}
        assert record == {
            "type": "local",
            "command": ["node", str(deployment / "repo/cli.js"), "--config",
                        str(directory / "etc/playwright-mcp-git/playwright.json")],
        }
        browser = config["browser"]
        assert browser["browserName"] == "firefox"
        assert browser["launchOptions"]["headless"] is False
        assert browser["userDataDir"] == str(directory / "var/playwright-mcp-git/profile")
        assert browser["initScript"] == [str(directory / "etc/playwright-mcp-git/automation-masking.js")]
        masking = (directory / "etc/playwright-mcp-git/automation-masking.js").read_text()
        assert "webdriver" in masking and "return false" in masking
        assert config["outputDir"] == str(directory / "var/playwright-mcp-git/output")
        assert "saveSession" not in config and "sharedBrowserContext" not in config
        assert "storageState" not in browser["contextOptions"]
        assert "chromiumSandbox" not in browser["launchOptions"]
        assert "${" not in json.dumps(record)
        install = (deployment / "bin/install.sh").read_text()
        assert f"cd {deployment}/repo" in install
        assert "npm ci" in install and "pnpm link" not in install
        download = (deployment / "bin/install-browser.sh").read_text()
        assert 'node cli.js install-browser firefox "$@"' in download
        render("playwright-mcp.src.pb", directory,
               PLAYWRIGHT_BROWSER="chromium", PLAYWRIGHT_HEADLESS=True,
               MCP_ENV={"DISPLAY": ":test", "XDG_RUNTIME_DIR": "/runtime/test"})
        overridden = json.loads((deployment / "etc/playwright.json").read_text())
        assert overridden["browser"]["browserName"] == "chromium"
        assert overridden["browser"]["launchOptions"]["headless"] is True
        assert json.loads((deployment / "etc/mcp.json").read_text())["environment"] == {
            "DISPLAY": ":test", "XDG_RUNTIME_DIR": "/runtime/test",
        }


def test_playwright_cli() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="render-cli-", dir=SCRATCH) as tmp:
        deployment = render("playwright-cli.opt.pb", Path(tmp))
        assert (deployment / "etc/npm.txt").read_text().strip() == "@playwright/cli@latest"
        assert not (deployment / "etc/mcp.json").exists()
        assert "pnpm install -g" in (deployment / "bin/install-npm.sh").read_text()


if __name__ == "__main__":
    test_playwright_mcp()
    test_playwright_cli()
    print("ok: Playwright native config and portable MCP/CLI playbooks")
