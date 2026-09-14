"""Compile attributed Ansible artifacts into a read-only runtime catalog."""

from __future__ import annotations

import collections.abc
import copy
import re

from ansible.errors import AnsibleFilterError
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


_ACTION = re.compile(r"^(build|install|apply)(?:-|\.|$)")
_ROOT = re.compile(r"^(build|install)(?:-([A-Za-z0-9_-]+))?\.sh$")
_SAFE = re.compile(r"[^a-z0-9]+")
_PHASE_INDEX = {
    "build": {"packages": 10, "identity": 20, "main": 50, "units": 75, "records": 95},
    "install": {"packages": 10, "identity": 25, "main": 40, "units": 75, "records": 95},
    "status": {"main": 50},
}
_PHASE_NAME = {
    "build": {"packages": "prerequisites", "identity": "prepare", "main": "compile", "units": "package", "records": "finalize"},
    "install": {"packages": "prerequisites", "identity": "identity", "main": "materialize", "units": "activate", "records": "record"},
    "status": {"main": "inspect"},
}


def _error(message):
    raise AnsibleFilterError("runtime_catalog: {}".format(message))


def _list(value, label):
    value = raw_copy_template_data(value)
    if value is None or value is False or wrapped_test_undefined(value):
        return []
    if isinstance(value, collections.abc.Mapping) or isinstance(value, str):
        return [value]
    if isinstance(value, collections.abc.Sequence) and not isinstance(value, (str, bytes)):
        return list(value)
    _error("{} must be a record or list".format(label))


def _refs(record):
    values = record.get("contributors", []) if isinstance(record, collections.abc.Mapping) else []
    if isinstance(values, str):
        values = [values]
    result = []
    for value in values:
        if isinstance(value, str) and value and value not in result:
            result.append(value)
    return result


def _name(record):
    if isinstance(record, str):
        return record
    if isinstance(record, collections.abc.Mapping):
        return record.get("dest", record.get("name"))
    return None


def _slug(value):
    value = _SAFE.sub("-", str(value).lower()).strip("-")
    return value or "entry"


def _legacy_action(record, name):
    explicit = record.get("action") if isinstance(record, collections.abc.Mapping) else None
    if isinstance(explicit, str) and explicit:
        return explicit, "explicit"
    match = _ACTION.match(name)
    return (match.group(1), "filename") if match else (None, None)


def _phase_for(name, bins_by_name, seen=None):
    seen = set(seen or [])
    if name in seen:
        return "main"
    seen.add(name)
    record = bins_by_name.get(name, {})
    phase = record.get("phase")
    if isinstance(phase, str) and phase:
        return phase
    children = record.get("run_all", [])
    child_phases = [_phase_for(child, bins_by_name, seen) for child in children]
    order = ["packages", "identity", "main", "units", "records"]
    return min(child_phases, key=order.index) if child_phases else "main"


def _invocation_file(flow, scope, child, sequence, bins_by_name):
    phase = _phase_for(child, bins_by_name)
    index = _PHASE_INDEX[flow].get(phase, _PHASE_INDEX[flow]["main"])
    effective_phase = _PHASE_NAME[flow].get(phase, "legacy-main")
    identity = "legacy:{}:{}:{}".format(flow, scope or "system", child)
    filename = "{:02d}-{}-{:03d}-{}.json".format(index, flow, sequence, _slug(child))
    record = bins_by_name.get(child, {})
    return filename, {
        "version": 1,
        "id": identity,
        "flow": flow,
        "scope": scope or "system",
        "index": index,
        "phase": effective_phase,
        "declaredPhase": "legacy-{}".format(phase),
        "native": False,
        "invoke": {
            "action": "command:{}".format(child),
            "handler": {"kind": "exec", "path": "bin/{}".format(child), "protocol": "legacy-exit-v1"},
        },
        "contributors": _refs(record),
        "source": {"kind": "legacy-bin", "name": child},
    }


def _resource_records(etc_files, links_plan, subsystems):
    resources = []
    names = set()
    for raw in _list(etc_files, "ETC_FILES"):
        name = raw.get("name") if isinstance(raw, collections.abc.Mapping) else raw
        if isinstance(name, str):
            names.add(name)
    config = subsystems.get("config", {}) if isinstance(subsystems, collections.abc.Mapping) else {}
    if isinstance(config, collections.abc.Mapping) and config.get("spec"):
        resources.append({"id": "config", "contract": "compfuzor.config/v2", "path": "etc/config.spec.json"})
    if "zim.spec.json" in names:
        resources.append({"id": "zim", "contract": "compfuzor.zim/v2", "path": "etc/zim.spec.json"})
    if isinstance(links_plan, collections.abc.Mapping) and links_plan.get("links"):
        resources.append({"id": "links", "contract": "compfuzor.links/v2", "path": "links.json"})
    return resources


@accept_args_markers
def compile_runtime_catalog(attribution, bins, statuses, links_plan=None, subsystems=None, etc_files=None):
    """Build catalog data and indexed legacy flow observations without executing them."""
    attribution = raw_copy_template_data(attribution)
    if not isinstance(attribution, collections.abc.Mapping):
        _error("attribution must be a deployment mapping")
    deployment_id = attribution.get("id")
    if not isinstance(deployment_id, str) or not deployment_id:
        _error("attribution requires an id")

    bin_records = [copy.deepcopy(dict(item)) for item in _list(bins, "BINS") if isinstance(item, collections.abc.Mapping)]
    bins_by_name = {name: item for item in bin_records if isinstance((name := _name(item)), str)}
    status_records = []
    for raw in _list(statuses, "STATUSES"):
        if isinstance(raw, str):
            status_records.append({"id": "legacy:{}".format(raw), "name": raw, "contributors": [deployment_id]})
        elif isinstance(raw, collections.abc.Mapping):
            status_records.append(copy.deepcopy(dict(raw)))

    contributor_ids = [deployment_id]
    family_counts = {}
    for family, records in (("BINS", bin_records), ("STATUSES", status_records)):
        for record in records:
            for contributor in _refs(record):
                if contributor not in contributor_ids:
                    contributor_ids.append(contributor)
                family_counts.setdefault(contributor, {}).setdefault(family, 0)
                family_counts[contributor][family] += 1
    if isinstance(links_plan, collections.abc.Mapping):
        for record in links_plan.get("links", []):
            for contributor in _refs(record):
                if contributor not in contributor_ids:
                    contributor_ids.append(contributor)
                family_counts.setdefault(contributor, {}).setdefault("LINKS", 0)
                family_counts[contributor]["LINKS"] += 1

    contributors = []
    for identity in contributor_ids:
        if identity == deployment_id:
            descriptor = copy.deepcopy(dict(attribution))
            descriptor["stage"] = "compile.foundation"
        else:
            kind, _, name = identity.partition(":")
            descriptor = {
                "id": identity,
                "kind": kind or "unknown",
                "name": name or identity,
                "requestedBy": deployment_id,
                "stage": "compile.synthesis",
            }
        descriptor["contributions"] = family_counts.get(identity, {})
        contributors.append(descriptor)

    commands = []
    actions = []
    for record in bin_records:
        name = _name(record)
        if not isinstance(name, str):
            continue
        command = {
            "id": "command:{}".format(name),
            "name": name,
            "path": "bin/{}".format(name),
            "contributors": _refs(record),
        }
        for field in ("scope", "subsystem", "phase", "compose", "run", "generated_by"):
            if field in record:
                command[field] = copy.deepcopy(record[field])
        commands.append(command)
        action, source = _legacy_action(record, name)
        if action:
            actions.append({
                "id": "command:{}".format(name),
                "action": action,
                "handler": {"kind": "exec", "path": "bin/{}".format(name), "protocol": "legacy-exit-v1"},
                "contributors": _refs(record),
                "source": {"kind": "legacy-bin", "classification": source},
            })

    files = []
    flows = {"build": [], "install": [], "status": []}
    for name, record in bins_by_name.items():
        match = _ROOT.fullmatch(name)
        if not match or record.get("generated_by") != "gen_bins":
            continue
        flow, scope = match.groups()
        for sequence, child in enumerate(record.get("run_all", []), start=1):
            filename, invocation = _invocation_file(flow, scope, child, sequence, bins_by_name)
            files.append({"name": filename, "invocation": invocation})
            flows[flow].append(invocation["id"])

    for sequence, status in enumerate(status_records, start=1):
        name = status.get("name")
        if not isinstance(name, str) or not name:
            continue
        filename = "50-status-{:03d}-{}.json".format(sequence, _slug(status.get("id", name)))
        invocation = {
            "version": 1,
            "id": "status:{}".format(status.get("id", name)),
            "flow": "status",
            "scope": "all",
            "index": 50,
            "phase": "inspect",
            "native": False,
            "invoke": {
                "action": "command:{}".format(name),
                "args": list(status.get("args", [])),
                "handler": {"kind": "exec", "path": "bin/{}".format(name), "protocol": "legacy-status-v1"},
            },
            "contributors": _refs(status),
            "source": {"kind": "legacy-status", "id": status.get("id")},
        }
        files.append({"name": filename, "invocation": invocation})
        flows["status"].append(invocation["id"])

    catalog = {
        "version": 1,
        "deployment": copy.deepcopy(dict(attribution)),
        "contributors": contributors,
        "resources": _resource_records(etc_files, links_plan, subsystems or {}),
        "commands": commands,
        "actions": actions,
        "flows": {name: {"name": name, "entries": entries} for name, entries in flows.items()},
        "execution": {"authority": "legacy-shell", "catalogOnly": True},
    }
    return {"catalog": catalog, "files": files}


class FilterModule(object):
    def filters(self):
        return {"runtime_catalog_compile": compile_runtime_catalog}
