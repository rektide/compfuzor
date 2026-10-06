#!/usr/bin/env python3
"""Controller tests for the opt-in lane; legacy tests remain separate."""
import sys
sys.path.insert(0, "library/filter_plugins")

from action_audiences import compile_action_audiences
from bin_composers import BIN_ACTIONS, bin_composers
from runtime_catalog import compile_runtime_catalog


def reject(operation, fragment):
    try:
        operation()
    except Exception as error:
        assert fragment in str(error), str(error)
    else:
        raise AssertionError("expected rejection: " + fragment)


def test_families():
    bins = [
        {"name": "install-packages.sh", "phase": "packages"},
        {"name": "install-config.sh", "scope": "user"},
        {"name": "install-service-user.sh", "subsystem": "systemd", "phase": "units"},
        {"name": "install-service.sh", "subsystem": "systemd", "phase": "units"},
        {"name": "assemble-owned.sh", "scope": ["user", "system"]},
        {"name": "build-src.sh"},
        {"name": "assemble-optout.sh", "compose": False},
        {"name": "install-old.sh", "state": "absent"},
    ]
    compiled = compile_action_audiences(bins, {})
    families = compiled["spec"]["actions"]
    install = families["install"]
    assert install["entry"] == "install-user.mjs"
    assert install["aliases"] == ["install.mjs", "install-system.mjs"]
    assert install["plans"]["user"] == [{"kind": "exec", "path": "bin/install-config.sh"}, {"kind": "action", "action": "install-systemd"}]
    assert install["plans"]["system"] == [{"kind": "exec", "path": "bin/install-packages.sh"}, {"kind": "action", "action": "install-systemd"}]
    assert families["install-systemd"]["plans"]["system"] == [{"kind": "exec", "path": "bin/install-service.sh"}]
    assert families["assemble"]["entry"] == "assemble-user.mjs"
    assert families["build"]["entry"] == "build-system.mjs"
    assert families["build"]["aliases"] == [] and "default" not in families["build"]
    assert BIN_ACTIONS == ("build", "install", "apply", "config")
    assert bin_composers([{"name": "assemble-leaf.sh"}]) == []
    assert bins[0] == {"name": "install-packages.sh", "phase": "packages"}  # no mutation

    system = compile_action_audiences(bins, {"default": "system"})["spec"]["actions"]["install"]
    assert system["entry"] == "install-system.mjs" and system["aliases"] == ["install.mjs", "install-user.mjs"]
    restricted = compile_action_audiences(bins, {"actions": {"install": False, "assemble": {"available": ["system"]}, "build": {"default": "system"}}})["spec"]["actions"]
    assert "install" not in restricted and "install-systemd" not in restricted
    assert restricted["assemble"]["aliases"] == []
    assert restricted["build"]["aliases"] == ["build.mjs"]
    empty = compile_action_audiences(bins, {"available": []})
    assert empty["spec"] == {"version": 1, "actions": {}}
    assert empty["etc_files"][0]["json"] == empty["spec"]
    assert compile_action_audiences([{"name": "install-user.sh"}], {})["spec"]["actions"] == {}
    assert sum(item.get("name") == "compfuzor-runtime.mjs" for item in compiled["bins"]) == 1

    reject(lambda: compile_action_audiences(bins, {"default": "user", "available": ["system"]}), "not in")
    assert compile_action_audiences(bins, {"actions": {"build": {"default": "user"}}})["spec"]["actions"]["build"]["aliases"] == []
    reject(lambda: compile_action_audiences(bins, {"available": False}), "must be a list")
    reject(lambda: compile_action_audiences(bins, {"available": ["user"], "actions": {"install": {"available": ["system"]}}}), "globally unavailable")
    reject(lambda: compile_action_audiences(bins, {"actions": {"bogus": False}}), "unknown actions")
    reject(lambda: compile_action_audiences([{"name": "install-x.sh", "scope": "shell"}], {}), "only user/system")
    reject(lambda: compile_action_audiences([{"name": "../install-x.sh", "action": "install"}], {}), "contained relative")
    reject(lambda: compile_action_audiences([{"name": "install-x.sh", "phase": "typo"}], {}), "unknown phase")
    reject(lambda: compile_action_audiences([{"name": "install-user.mjs", "compose": False}, {"name": "install-x-user.sh"}], {}), "collision")

    # Real entry imports shared implementation, not another omnibus copy.
    entry = next(item for item in compiled["bins"] if item["name"] == "install-user.mjs")
    assert entry["runtime"] == "node" and '"./compfuzor-runtime.mjs"' in entry["content"]
    assert "import.meta.url" in entry["content"] and "process.argv[1]" in entry["content"]


def test_body_and_catalog():
    compiled = compile_action_audiences([
        {"name": "install-user.sh", "content": "export BODY_STATE=yes", "late": "echo after", "bypass": "OWN", "run_all": ["manual.sh"]},
        {"name": "install-done-user.sh", "phase": "records", "subsystem": "bookkeeping"},
        {"name": "install-first-user.sh", "phase": "main"},
        {"name": "manual.sh", "compose": False},
    ], {})
    body = next(item for item in compiled["bins"] if "action_body" in item)
    assert body["run_all"] == ["manual.sh", "install-first-user.sh", "install-bookkeeping-user.mjs"]
    assert body["content"] == "export BODY_STATE=yes" and body["late"] == "echo after" and body["bypass"] == "OWN"
    assert body["name"] == "install-user.sh" and body["action_body"] == {"name": "install", "audience": "user", "path": "bin/install-user.sh"}
    plan = compiled["spec"]["actions"]["install"]["plans"]["user"]
    assert len(plan) == 1 and plan[0]["children"][0]["path"] == "bin/manual.sh"
    catalog = compile_runtime_catalog({"id": "deployment:demo"}, compiled["bins"], [], etc_files=compiled["etc_files"])
    assert catalog["catalog"]["execution"] == {"authority": "action-audiences", "catalogOnly": True}
    assert len(catalog["files"]) == 1
    invocation = catalog["files"][0]["invocation"]
    assert invocation["scope"] == "user" and invocation["invoke"]["handler"]["path"] == "bin/install-user.mjs"
    assert invocation["source"]["kind"] == "audience-action"
    assert any(resource["contract"] == "compfuzor.actions/v1" for resource in catalog["catalog"]["resources"])
    reject(lambda: compile_runtime_catalog({"id": "deployment:demo"}, compiled["bins"], [], execution_enabled=True), "unscoped native flow")


if __name__ == "__main__":
    test_families()
    test_body_and_catalog()
    print("ok: action audience compilation, omission, body preservation and catalog")
