"""Opt-in audience-qualified JavaScript action families over existing BINS leaves."""

from __future__ import annotations

import copy
import posixpath
import re
from collections.abc import Mapping

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from bin_composers import (
    BIN_ACTIONS, _arrayitize, _contributors, _resolve_phase, bin_composers,
)
from runtime_bundles import compfuzor_runtime_bin
from template_data import raw_copy_template_data


# Deliberately local: enabling this vocabulary must not change legacy composition.
ACTIONS = BIN_ACTIONS + ("assemble", "publish", "sync-inputs", "inputs")
AUDIENCES = ("user", "system")
SPEC_PATH = "compfuzor-actions/spec.json"
_ACTION = re.compile(r"^(" + "|".join(ACTIONS) + r")(?:-[A-Za-z0-9.\\][A-Za-z0-9._\\-]*)?(?:\.user)?\.(?:sh|mjs|ts)$")
_BODY = ("early", "content", "exec", "execs", "generated", "late", "src")


def fail(message):
    raise AnsibleFilterError("action_audiences: " + message)


def mapping(value, label):
    if not isinstance(value, Mapping):
        fail(label + " must be a mapping")
    return dict(value)


def audiences(value, label):
    values = _arrayitize(value)
    if any(not isinstance(item, str) or item not in AUDIENCES for item in values):
        fail(label + " must contain only user/system")
    if len(set(values)) != len(values):
        fail(label + " contains duplicate audiences")
    return values


def relative_bin(name):
    if not isinstance(name, str) or not name or posixpath.isabs(name) or ".." in name.split("/") or posixpath.normpath(name) != name:
        fail("bin name must be a contained relative path: {!r}".format(name))
    return name


def policy_settings(value, label, inherited=None):
    value = mapping(value, label)
    unknown = set(value) - {"default", "available"}
    if unknown:
        fail(label + " has unknown settings: " + ", ".join(sorted(unknown)))
    inherited = inherited or {"default": "user", "available": list(AUDIENCES)}
    result = {**inherited, **value}
    if result["default"] not in AUDIENCES:
        fail(label + ".default must be user/system")
    result["available"] = audiences(result["available"], label + ".available")
    # An inherited default may have no plan/shortcut. An explicitly contradictory
    # declaration is an error, not an invitation to run the other audience.
    if "default" in value and result["default"] not in result["available"]:
        fail(label + ".default is not in its declared available audiences")
    result["explicitDefault"] = "default" in value
    return result


def entry_record(name, action, family, contributors):
    return {
        "name": name,
        "runtime": "node",
        "action": action,
        "compose": False,
        "basedir": False,
        "generated_by": "gen_action_audiences",
        "audience_action": family,
        "contributors": contributors,
        "content": 'import { actionEntry } from "./compfuzor-runtime.mjs";\n'
                   'actionEntry(process.argv.slice(2), process.argv[1], import.meta.url);',
    }


@accept_args_markers
def compile_action_audiences(bins, policy):
    """Compile plans/entries; no execution, deletion, bundling or placement switch.

    The ordinary bin composer still owns phase/subsystem order. Authored root
    bodies are retained whole in a private shell bridge so body-local bypass,
    exported state and late blocks keep their existing semantics.
    """
    bins = copy.deepcopy(_arrayitize(raw_copy_template_data(bins)))
    policy = mapping(raw_copy_template_data(policy), "ACTION_AUDIENCES")
    unknown = set(policy) - {"default", "available", "actions"}
    if unknown:
        fail("ACTION_AUDIENCES has unknown settings: " + ", ".join(sorted(unknown)))
    base = policy_settings({key: value for key, value in policy.items() if key != "actions"}, "ACTION_AUDIENCES")
    overrides = mapping(policy.get("actions", {}), "ACTION_AUDIENCES.actions")
    if set(overrides) - set(ACTIONS):
        fail("unknown actions: " + ", ".join(sorted(set(overrides) - set(ACTIONS))))
    settings = {}
    for action in ACTIONS:
        value = overrides.get(action, {})
        settings[action] = None if value is False else policy_settings(value, "ACTION_AUDIENCES.actions." + action, base)

    normalized, roots, retained = [], {}, []
    occupied = {item.get("dest", item.get("name")) for item in bins if isinstance(item, Mapping)}
    for item in bins:
        if not isinstance(item, Mapping) or item.get("state") == "absent" or item.get("compose") is False:
            retained.append(item)
            continue
        if item.get("generated_by") in ("gen_bins", "gen_action_audiences"):
            fail("compile before generating action compositors, not from previously generated BINS")
        name = item.get("dest", item.get("name"))
        match = _ACTION.fullmatch(name) if isinstance(name, str) else None
        action = item.get("action") or (match.group(1) if match else None)
        if action is None:
            retained.append(item)
            continue
        if action not in ACTIONS:
            fail("unknown action {!r} on bin {!r}".format(action, name))
        relative_bin(name)
        phase = _resolve_phase(item)
        inferred = "user" if name.endswith(("-user.sh", "-user.mjs", "-user.ts", ".user.sh", ".user.mjs", ".user.ts")) or name.startswith(action + "-user-") else "system"
        scopes = audiences(item["scope"], "bin {!r}.scope".format(name)) if "scope" in item and _arrayitize(item["scope"]) else [inferred]
        root_names = {action + ext: "system" for ext in (".sh", ".mjs", ".ts")}
        root_names.update({action + "-" + audience + ext: audience for audience in AUDIENCES for ext in (".sh", ".mjs", ".ts")})
        if name in root_names:
            if scopes != [root_names[name]]:
                fail("authored root {!r} must match its {} audience".format(name, root_names[name]))
            key = (action, scopes[0])
            if key in roots:
                fail("multiple authored roots for {} {}".format(*key))
            if item.get("raw") or item.get("link") or item.get("runtime", "shell") != "shell" or "src" in item:
                fail("authored action roots require inline shell bodies; use a named composing leaf for source/raw/node commands")
            roots[key] = item
        else:
            retained.append(item)
            normalized.append({**item, "name": name, "action": action, "scope": scopes, "phase": phase})

    # Reuse the existing composer rather than duplicating its lane schedule.
    composed = bin_composers(normalized, actions=ACTIONS)
    groups = {}
    comp_keys = {}
    for comp in composed:
        action = comp["action"]
        audience = comp["scope"][0]
        name = comp["name"][:-len("-" + audience + ".sh")]
        groups.setdefault(name, {"action": action, "plans": {}})["plans"][audience] = comp["run_all"]
        comp_keys[comp["name"]] = name
    for action, audience in roots:
        groups.setdefault(action, {"action": action, "plans": {}})["plans"].setdefault(audience, [])

    spec = {"version": 1, "actions": {}}
    generated = []
    for name, group in groups.items():
        action = group["action"]
        config = settings[action]
        if config is None:
            continue
        available = [audience for audience in AUDIENCES if audience in config["available"] and audience in group["plans"]]
        if config["explicitDefault"] and config["default"] not in available and name == action:
            fail("{} explicitly defaults to an audience with no contributed plan: {}".format(action, config["default"]))
        if not available:
            continue
        default = config["default"] if config["default"] in available else None
        physical_audience = default or available[0]
        entry = name + "-" + physical_audience + ".mjs"
        aliases = [name + "-" + audience + ".mjs" for audience in available if audience != physical_audience]
        if default is not None:
            aliases.insert(0, name + ".mjs")
        for generated_name in [entry, *aliases]:
            if generated_name in occupied:
                fail("generated action entry collision: " + generated_name)
            occupied.add(generated_name)
        plans = {}
        members = [item for item in normalized if item["action"] == action]
        contributors = _contributors(members + [item for (root_action, _), item in roots.items() if root_action == action])
        for audience in available:
            steps = []
            root = roots.get((name, audience))
            authored_children = _arrayitize(root.get("run_all")) if root is not None else []
            children = authored_children + group["plans"][audience]
            for child in children:
                relative_bin(child)
                if child in comp_keys:
                    steps.append({"kind": "action", "action": comp_keys[child]})
                else:
                    steps.append({"kind": "exec", "path": "bin/" + child})
            if root is not None:
                private = "internal/action-audiences/" + name + "-" + audience + ".sh"
                if private in occupied:
                    fail("private action body collision: " + private)
                occupied.add(private)
                children = [comp_keys[child] + "-" + audience + ".mjs" if child in comp_keys else child for child in children]
                generated.append({**root, "name": private, "dest": private, "generated_by": "gen_bins", "compose": False, "run_all": children, "deployment_rooted": True, "deployment_root_relative": "../../..", "action_report_name": root.get("name"), "action": action, "scope": [audience]})
                steps = [{"kind": "exec", "path": "bin/" + private, "children": steps}]
            plans[audience] = steps
        family = {"name": name, "action": action, "entry": entry, "aliases": aliases, "plans": plans}
        if default is not None:
            family["default"] = default
        spec["actions"][name] = family
        generated.append(entry_record(entry, action, family, contributors))
        for alias in aliases:
            generated.append({"name": alias, "dest": alias, "link": entry, "force": True, "action": action, "compose": False, "basedir": False, "generated_by": "gen_action_audiences", "contributors": contributors})

    # Always publish even an empty spec: old action entries must become unable
    # to execute when a policy removes all actions. Do not prune those entries.
    if "compfuzor-runtime.mjs" not in occupied:
        generated.append(compfuzor_runtime_bin())
    return {
        "bins": retained + generated,
        "spec": spec,
        "etc_files": [{"name": SPEC_PATH, "json": spec}],
        "etc_dirs": ["compfuzor-actions"],
        "bin_dirs": ["internal", "internal/action-audiences"],
    }


class FilterModule(object):
    def filters(self):
        return {"action_audiences_compile": compile_action_audiences}
