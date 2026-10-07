#!/usr/bin/env python3
"""Zim exact offer packaging and passive owner endpoints, without scanning directories."""
import sys
sys.path.insert(0, "library/filter_plugins")
from registry_compile import zim_registry
from zim_fragment import zim_fragment

def test_compile():
    fragments = zim_fragment([{"name": "shell-tools", "env": {"EDITOR": "vim"}}, {"name": "retained", "source": "owner/repo", "enabled": False}], phase="tools", etc="/owner/etc")
    compiled = zim_registry(fragments, "shell-owner", "/owner/etc")
    offer = compiled["files"][0]["json"]
    assert offer["id"] == "shell-owner" and len(offer["fragments"]) == 2
    assert {record["enabled"] for record in offer["fragments"]} == {True, False}
    assert all(record["path"].startswith("/owner/etc/zim/") for record in offer["fragments"])
    assert all(record["name"].endswith(".conf") for record in offer["fragments"])
    endpoints = [entry for entry in compiled["bins"] if entry["name"] in ("register-zim-provider.sh", "status-zim-provider.sh")]
    assert len(endpoints) == 2 and all(entry["compose"] is False for entry in endpoints)
    assert all("--source /owner/etc/zim-provider.json" in entry["content"] for entry in endpoints)
    print("ok: exact generated Zim offers, retained fragment disable and passive registration endpoints")

if __name__ == "__main__":
    test_compile()
