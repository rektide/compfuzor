"""Compile named drop-in sets and config assembly graphs into shared artifacts."""

from __future__ import annotations

import collections.abc
import posixpath
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_PROCESSORS = {"concat", "json-deep-merge"}


def _error(message):
    raise AnsibleFilterError("config_compile: {}".format(message))


def _mapping(value, label):
    if value is None:
        return {}
    if not isinstance(value, collections.abc.Mapping):
        _error("{} must be a mapping".format(label))
    return dict(value)


def _identifier(value, label):
    if not isinstance(value, str) or not _ID.fullmatch(value):
        _error("{} must match {}".format(label, _ID.pattern))
    return value


def _path(root, value, label):
    if not isinstance(value, str) or not value:
        _error("{} must be a non-empty path".format(label))
    if value.startswith("~"):
        _error("{} must not use an unexpanded '~' path".format(label))
    if value.startswith("/"):
        return posixpath.normpath(value)
    if not isinstance(root, str) or not root:
        _error("{} requires a root for relative path {!r}".format(label, value))
    return posixpath.normpath(posixpath.join(root, value))


def _sequence(value, label):
    if not isinstance(value, collections.abc.Sequence) or isinstance(value, (str, bytes)):
        _error("{} must be a sequence".format(label))
    return list(value)


def _topological_order(assemblies, config_id):
    dependencies = {}
    for assembly_id, assembly in assemblies.items():
        dependencies[assembly_id] = [
            item["artifact"]
            for item in assembly["inputs"]
            if "artifact" in item
        ]

    visiting = set()
    visited = set()
    ordered = []

    def visit(assembly_id):
        if assembly_id in visited:
            return
        if assembly_id in visiting:
            _error("config {!r} assembly graph contains a cycle at {!r}".format(config_id, assembly_id))
        visiting.add(assembly_id)
        for dependency in dependencies[assembly_id]:
            if dependency not in assemblies:
                _error(
                    "config {!r} assembly {!r} references unknown artifact {!r}".format(
                        config_id, assembly_id, dependency
                    )
                )
            visit(dependency)
        visiting.remove(assembly_id)
        visited.add(assembly_id)
        ordered.append(assembly_id)

    for assembly_id in assemblies:
        visit(assembly_id)
    return ordered


@accept_args_markers
def compile_config(dropins, configs):
    """Return normalized config spec plus filesystem/bin/status contributions."""
    dropins = _mapping(raw_copy_template_data(dropins), "DROPINS")
    configs = _mapping(raw_copy_template_data(configs), "CONFIGS")

    normalized_dropins = {}
    dirs = []
    files = []
    for dropin_id, raw in dropins.items():
        dropin_id = _identifier(dropin_id, "drop-in id")
        raw = _mapping(raw, "DROPINS.{}".format(dropin_id))
        root = raw.get("root")
        path = _path(root, raw.get("path"), "DROPINS.{}.path".format(dropin_id))
        include = raw.get("include")
        if not isinstance(include, str) or not include:
            _error("DROPINS.{}.include must be a non-empty glob".format(dropin_id))
        suffix = raw.get("disabled_suffix")
        if suffix is not None and (not isinstance(suffix, str) or not suffix.startswith(".")):
            _error("DROPINS.{}.disabled_suffix must start with '.'".format(dropin_id))

        normalized_dropins[dropin_id] = {
            "path": path,
            "include": include,
            "disabled_suffix": suffix,
        }
        if path not in dirs:
            dirs.append(path)

        for index, item in enumerate(_sequence(raw.get("files", []), "DROPINS.{}.files".format(dropin_id))):
            if isinstance(item, str):
                item = {"name": item}
            if not isinstance(item, collections.abc.Mapping):
                _error("DROPINS.{}.files[{}] must be a string or mapping".format(dropin_id, index))
            item = dict(item)
            name = item.get("dest", item.get("name"))
            item["dest"] = _path(path, name, "DROPINS.{}.files[{}] destination".format(dropin_id, index))
            files.append(item)

    normalized_configs = {}
    output_owners = {}
    bins = [
        {
            "name": "config.sh",
            "src": "../config-run.sh",
            "basedir": False,
            "run": True,
            "requires_fs": True,
        },
        {
            "name": "config-toggle.sh",
            "src": "../config-toggle.sh",
            "basedir": False,
        },
    ] if configs else []
    statuses = []

    for config_id, raw in configs.items():
        config_id = _identifier(config_id, "config id")
        raw = _mapping(raw, "CONFIGS.{}".format(config_id))
        root = raw.get("root")
        assemblies_raw = _mapping(raw.get("assemblies"), "CONFIGS.{}.assemblies".format(config_id))
        if not assemblies_raw:
            _error("CONFIGS.{}.assemblies must not be empty".format(config_id))

        assemblies = {}
        referenced_dropins = []
        for assembly_id, assembly_raw in assemblies_raw.items():
            assembly_id = _identifier(assembly_id, "assembly id")
            assembly_raw = _mapping(
                assembly_raw,
                "CONFIGS.{}.assemblies.{}".format(config_id, assembly_id),
            )
            output = _path(
                root,
                assembly_raw.get("output"),
                "CONFIGS.{}.assemblies.{}.output".format(config_id, assembly_id),
            )
            owner = output_owners.get(output)
            if owner is not None:
                _error("output {!r} is claimed by {} and {}".format(output, owner, config_id + "." + assembly_id))
            output_owners[output] = config_id + "." + assembly_id
            output_dir = posixpath.dirname(output)
            if output_dir and output_dir not in dirs:
                dirs.append(output_dir)

            processor = assembly_raw.get("processor")
            if processor not in _PROCESSORS:
                _error("unsupported processor {!r}".format(processor))
            validate = assembly_raw.get("validate")
            if validate is not None and (not isinstance(validate, str) or not validate):
                _error("assembly validate must be a non-empty command")

            inputs = []
            for index, item in enumerate(
                _sequence(
                    assembly_raw.get("inputs"),
                    "CONFIGS.{}.assemblies.{}.inputs".format(config_id, assembly_id),
                )
            ):
                if not isinstance(item, collections.abc.Mapping) or len(item) != 1:
                    _error("config inputs must contain exactly one typed reference")
                kind, value = next(iter(item.items()))
                if kind == "file":
                    inputs.append({"file": _path(root, value, "config file input")})
                elif kind == "dropins":
                    if value not in normalized_dropins:
                        _error("config {!r} references unknown drop-in {!r}".format(config_id, value))
                    inputs.append({"dropins": value})
                    if value not in referenced_dropins:
                        referenced_dropins.append(value)
                elif kind == "artifact":
                    inputs.append({"artifact": value})
                else:
                    _error("unknown config input type {!r}".format(kind))

            assemblies[assembly_id] = {
                "output": output,
                "processor": processor,
                "inputs": inputs,
                "validate": validate,
            }

        order = _topological_order(assemblies, config_id)
        for assembly in assemblies.values():
            for item in assembly["inputs"]:
                if "artifact" in item:
                    artifact = item["artifact"]
                    item["path"] = assemblies[artifact]["output"]

        normalized_configs[config_id] = {
            "apply": bool(raw.get("apply", True)),
            "order": order,
            "assemblies": assemblies,
            "dropins": referenced_dropins,
        }

        bins.append({
            "name": "config-{}.sh".format(config_id),
            "basedir": False,
            "content": 'exec "$DIR/bin/config.sh" {} "$@"'.format(config_id),
        })
        if any(normalized_dropins[name]["disabled_suffix"] for name in referenced_dropins):
            for action in ("disable", "enable"):
                bins.append({
                    "name": "{}-{}.sh".format(action, config_id),
                    "basedir": False,
                    "content": 'exec "$DIR/bin/config-toggle.sh" {} {} "$@"'.format(
                        action, config_id
                    ),
                })
        status_name = "status-config-{}.sh".format(config_id)
        bins.append({
            "name": status_name,
            "basedir": False,
            "content": 'exec "$DIR/bin/config-{}.sh" --check "$@"'.format(config_id),
        })
        statuses.append(status_name)

    return {
        "dirs": dirs,
        "files": files,
        "spec": {
            "dropins": normalized_dropins,
            "configs": normalized_configs,
        },
        "bins": bins,
        "statuses": statuses,
    }


class FilterModule(object):
    def filters(self):
        return {"config_compile": compile_config}
