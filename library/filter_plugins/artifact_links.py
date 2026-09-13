"""Compile filesystem declarations and deferred link plans."""

from __future__ import annotations

import collections.abc
import posixpath
import re

from ansible.errors import AnsibleFilterError
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

_POLICIES = {"preserve", "fail", "replace"}
_SCOPES = {"system", "user"}
_STRATEGIES = {"link", "copy"}
_RUNTIME_ROOT = re.compile(r"^\$\{(HOME|XDG_RUNTIME_DIR|XDG_STATE_HOME)\}(?:/|$)")


def _error(message):
    raise AnsibleFilterError("artifact_links: {}".format(message))


def _truthy(value):
    if value is None or wrapped_test_undefined(value):
        return False
    if isinstance(value, str):
        return value.strip().lower() not in {"", "0", "false", "no", "off", "none"}
    return bool(value)


def _array(value, label):
    if value is None or wrapped_test_undefined(value) or value is False:
        return []
    if isinstance(value, collections.abc.Mapping):
        return [dict(value)]
    if isinstance(value, collections.abc.Sequence) and not isinstance(value, (str, bytes)):
        return list(value)
    if isinstance(value, str):
        return [value]
    _error("{} must be a list, mapping, or string".format(label))


def _list(value, label):
    if not isinstance(value, collections.abc.Sequence) or isinstance(value, (str, bytes)):
        _error("{} must be a list".format(label))
    return list(value)


def _default_dir(path, base, label):
    if not isinstance(path, str) or not path:
        _error("{} must resolve to a non-empty string".format(label))
    if path.startswith(("/", "~")):
        return path
    if not isinstance(base, str) or not base:
        _error("{} requires a base directory".format(label))
    return base + "/" + path


def _normalize_family_items(value, family):
    if value is None or wrapped_test_undefined(value) or value is False:
        return []
    if isinstance(value, collections.abc.Mapping):
        return [{"dest": dest, "src": src} for dest, src in value.items()]
    return _array(value, family)


def _first_truthy(*values):
    for value in values:
        if _truthy(value):
            return value
    return None


def _artifact_entry(item, family, kind, root, index):
    if isinstance(item, collections.abc.Mapping):
        declaration = dict(item)
        if "destTemplate" in declaration:
            _error("{}.{} uses retired destTemplate; use dest".format(family, index))
        destination = _first_truthy(
            declaration.get("dest"),
            declaration.get("name"),
            declaration.get("src"),
        )
        writer = "line" if _truthy(declaration.get("line")) else "copy"
    elif isinstance(item, str):
        declaration = item
        destination = item
        writer = "copy"
    else:
        _error("{}[{}] must be a mapping or string".format(family, index))

    resolved = _default_dir(destination, root, "{}[{}] destination".format(family, index))
    relative = destination if not destination.startswith(("/", "~")) else None
    identity = (
        _first_truthy(declaration.get("name"), declaration.get("dest"), declaration.get("src"))
        if isinstance(declaration, dict)
        else declaration
    )
    return {
        "family": family,
        "kind": kind,
        "writer": writer,
        "identity": str(identity),
        "materialized_root": root,
        "relative_dest": relative,
        "resolved_dest": resolved,
        "origin": {"family": family, "index": index, "identity": str(identity)},
        "item": declaration,
    }


@accept_args_markers
def compile_artifacts(context):
    """Compile FILES and DIRSET-derived *_FILES from an Ansible vars mapping."""
    if not isinstance(context, collections.abc.Mapping):
        _error("compile_artifacts input must be the Ansible vars mapping")
    directory = context.get("DIR")
    name = context.get("NAME")
    if not isinstance(directory, str) or not directory:
        _error("DIR must be a non-empty string")
    if not isinstance(name, str) or not name:
        _error("NAME must be a non-empty string")

    dirset = _array(context.get("DIRSET", []), "DIRSET")
    specs = [("FILES", None, directory, directory)]
    for raw_kind in dirset:
        if not isinstance(raw_kind, str) or not raw_kind:
            _error("DIRSET entries must be non-empty strings")
        kind = raw_kind.lower()
        upper = kind.upper()
        fsh_root = context.get(upper)
        if not isinstance(fsh_root, str) or not fsh_root:
            base = context.get(upper + "S_DIR")
            if isinstance(base, str) and base:
                fsh_root = base + "/" + name
            else:
                continue
        dir_root = directory + "/" + kind
        if _truthy(context.get("FS_CONTAINERED")):
            materialized, exposure = dir_root, fsh_root
        else:
            materialized, exposure = fsh_root, dir_root
        specs.append((upper + "_FILES", kind, materialized, exposure))

    families = {}
    copies = []
    lines = []
    fs_bypassed = _truthy(context.get("FS_BYPASS")) or _truthy(context.get("DIR_BYPASS"))
    for family, kind, materialized, exposure in specs:
        family_bypassed = fs_bypassed or (kind is not None and _truthy(context.get(kind.upper() + "_BYPASS")))
        items = [] if family_bypassed else _normalize_family_items(context.get(family), family)
        entries = [
            _artifact_entry(item, family, kind, materialized, index)
            for index, item in enumerate(items)
        ]
        families[family] = {
            "kind": kind,
            "materialized_root": materialized,
            "exposure_root": exposure,
            "bypassed": family_bypassed,
            "entries": entries,
        }
        for entry in entries:
            (lines if entry["writer"] == "line" else copies).append(entry)

    return {"families": families, "copies": copies, "lines": lines}


@accept_args_markers
def artifacts_have_links(artifacts):
    """Return whether compiled artifacts contain link or links annotations."""
    if not isinstance(artifacts, collections.abc.Mapping):
        return False
    for family in artifacts.get("families", {}).values():
        for artifact in family.get("entries", []):
            item = artifact.get("item")
            if isinstance(item, collections.abc.Mapping) and (
                item.get("link") not in (None, False)
                or item.get("links") not in (None, False)
            ):
                return True
    return False


def _runtime_roots(path):
    roots = []
    match = _RUNTIME_ROOT.match(path)
    if match:
        roots.append(match.group(1))
    elif "$" in path:
        _error("unsupported runtime expression in {!r}".format(path))
    if path.startswith("~") and path != "~" and not path.startswith("~/"):
        _error("unsupported home expression in {!r}".format(path))
    return roots


def _link_path(value, scope, directory, roots, label):
    if isinstance(value, str):
        if value.startswith("${"):
            _runtime_roots(value)
            return value
        return _default_dir(value, directory, label)
    if not isinstance(value, collections.abc.Mapping):
        _error("{} must be a path or fsh mapping".format(label))
    unknown = set(value) - {"fsh", "name"}
    if unknown:
        _error("{} has unknown fields: {}".format(label, ", ".join(sorted(unknown))))
    kind = value.get("fsh")
    relative = value.get("name")
    if not isinstance(kind, str) or kind not in roots.get(scope, {}):
        _error("{} references unknown {} fsh kind {!r}".format(label, scope, kind))
    if not isinstance(relative, str) or not relative:
        _error("{}.name must be a non-empty string".format(label))
    return roots[scope][kind] + "/" + relative


def _record_id(scope, dest):
    return "{}:{}".format(scope, posixpath.normpath(dest))


def _normalize_strategies(value, origin):
    if not isinstance(value, collections.abc.Mapping):
        _error("{} strategies must be a mapping".format(origin))
    unknown = set(value) - {"available", "default"}
    if unknown:
        _error("{} strategies has unknown fields: {}".format(origin, ", ".join(sorted(unknown))))
    available = value.get("available")
    if not isinstance(available, collections.abc.Sequence) or isinstance(available, (str, bytes)) or not available:
        _error("{} strategies.available must be a non-empty list".format(origin))
    available = list(available)
    if any(strategy not in _STRATEGIES for strategy in available):
        _error("{} strategies.available may contain only link or copy".format(origin))
    if len(set(available)) != len(available):
        _error("{} strategies.available contains duplicates".format(origin))
    available = [strategy for strategy in ("link", "copy") if strategy in available]
    default = value.get("default")
    if default not in _STRATEGIES:
        _error("{} strategies.default must be link or copy".format(origin))
    if default not in available:
        _error("{} strategies.default must be available".format(origin))
    return {"available": available, "default": default}


def _link_comparable(record):
    comparable = {key: value for key, value in record.items() if key not in {"origin", "origins"}}
    comparable.setdefault("strategies", {"available": ["link"], "default": "link"})
    comparable.setdefault("compose", True)
    return comparable


def _normalize_link(raw, directory, roots, origin, default_src=None, inferred=None, index=0):
    if isinstance(raw, str):
        if raw == "user" and inferred is not None:
            raw = {"scope": "user"}
        else:
            raw = {"dest": raw}
    if not isinstance(raw, collections.abc.Mapping):
        _error("{} link must be a string or mapping".format(origin))
    item = dict(raw)
    unknown = set(item) - {"id", "src", "dest", "scope", "policy", "state", "strategies", "compose"}
    if unknown:
        _error("{} link has unknown fields: {}".format(origin, ", ".join(sorted(unknown))))
    if default_src is not None and "src" in item:
        _error("{} annotation cannot override src".format(origin))

    scope = item.get("scope", "system")
    if scope not in _SCOPES:
        _error("{} has unknown scope {!r}".format(origin, scope))
    policy = item.get("policy", "preserve")
    if policy not in _POLICIES:
        _error("{} has unknown policy {!r}".format(origin, policy))
    state = item.get("state", "present")
    if state not in {"present", "absent"}:
        _error("{} has unknown state {!r}".format(origin, state))
    strategies = _normalize_strategies(item["strategies"], origin) if "strategies" in item else None
    compose = item.get("compose", True)
    if not isinstance(compose, bool):
        _error("{} compose must be boolean".format(origin))

    src_value = default_src if default_src is not None else item.get("src")
    if not isinstance(src_value, str) or not src_value:
        _error("{} requires src".format(origin))
    src = src_value if src_value.startswith("${") else _default_dir(src_value, directory, "{}.src".format(origin))

    dest_value = item.get("dest")
    if dest_value is None and inferred is not None and scope == "user":
        if inferred.get("kind") is None:
            _error("{} has no fsh kind for link: user".format(origin))
        if inferred.get("relative_dest") is None:
            _error("{} has no family-relative destination for link: user".format(origin))
        root = roots.get("user", {}).get(inferred["kind"])
        if not root:
            _error("{} has no user fsh root for {!r}".format(origin, inferred["kind"]))
        dest = root + "/" + inferred["relative_dest"]
    elif dest_value is None:
        _error("{} requires dest".format(origin))
    else:
        dest = _link_path(dest_value, scope, directory, roots, "{}.dest".format(origin))

    if posixpath.normpath(src) == posixpath.normpath(dest):
        _error("{} source and destination are the same path".format(origin))
    record_id = item.get("id") or _record_id(scope, dest)
    if not isinstance(record_id, str) or not record_id:
        _error("{} id must be a non-empty string".format(origin))
    record = {
        "id": record_id,
        "origin": origin,
        "scope": scope,
        "src": src,
        "dest": dest,
        "runtimeRoots": sorted(set(_runtime_roots(src) + _runtime_roots(dest))),
        "policy": policy,
        "state": state,
    }
    if strategies is not None:
        record["strategies"] = strategies
    if "compose" in item:
        record["compose"] = compose
    return record


@accept_args_markers
def compile_links(links, artifacts, directory, name, roots):
    """Combine explicit LINKS and compiled artifact annotations into one plan."""
    if isinstance(links, collections.abc.Mapping):
        _error("LINKS must be a list; mapping shorthand was removed")
    explicit = _array(links, "LINKS")
    if not isinstance(artifacts, collections.abc.Mapping):
        _error("artifacts must be compiled artifact data")
    if not isinstance(roots, collections.abc.Mapping):
        _error("fsh roots must be a scope mapping")

    records = []
    for index, item in enumerate(explicit):
        records.append(
            _normalize_link(item, directory, roots, {"type": "explicit", "index": index}, index=index)
        )

    for family_name, family in artifacts.get("families", {}).items():
        for artifact in family.get("entries", []):
            declaration = artifact.get("item")
            if not isinstance(declaration, collections.abc.Mapping):
                continue
            annotations = []
            if "link" in declaration and declaration["link"] not in (None, False):
                annotations.append(("link", declaration["link"]))
            if "links" in declaration and declaration["links"] not in (None, False):
                for annotation_index, annotation in enumerate(_list(declaration["links"], "{}.links".format(family_name))):
                    annotations.append(("links[{}]".format(annotation_index), annotation))
            for annotation_index, (field, annotation) in enumerate(annotations):
                origin = {
                    "type": "artifact",
                    "family": family_name,
                    "index": artifact["origin"]["index"],
                    "identity": artifact["identity"],
                    "field": field,
                }
                records.append(
                    _normalize_link(
                        annotation,
                        directory,
                        roots,
                        origin,
                        default_src=artifact["resolved_dest"],
                        inferred=artifact if field == "link" and annotation == "user" else None,
                        index=annotation_index,
                    )
                )

    by_id = {}
    by_dest = {}
    output = []
    for record in records:
        identity = record["id"]
        dest_key = (record["scope"], posixpath.normpath(record["dest"]))
        comparable = _link_comparable(record)
        if dest_key in by_dest:
            previous = by_dest[dest_key]
            previous_comparable = _link_comparable(previous)
            if previous_comparable != comparable:
                _error("destination {!r} in scope {} has conflicting records".format(record["dest"], record["scope"]))
            previous.setdefault("origins", [previous["origin"]]).append(record["origin"])
            continue
        if identity in by_id and by_id[identity] != comparable:
            _error("link id {!r} has conflicting records".format(identity))
        by_id[identity] = comparable
        by_dest[dest_key] = record
        output.append(record)

    return {
        "version": 2,
        "deployment": {"id": name, "name": name, "dir": directory},
        "links": output,
    }


class FilterModule(object):
    def filters(self):
        return {
            "compile_artifacts": compile_artifacts,
            "artifacts_have_links": artifacts_have_links,
            "compile_links": compile_links,
        }
