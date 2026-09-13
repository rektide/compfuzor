"""Bind compiled CONFIGS recipes to reusable consumer contexts."""

from __future__ import annotations

import collections.abc
import copy
import json
import posixpath
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from config_selectors import compile_path_selector, relative_path
from template_data import raw_copy_template_data
from runtime_bundles import links_runtime_bins, links_runtime_dirs


_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_CANONICAL = "canonical"
_ACTIONS = ("install", "assemble", "sync-inputs", "publish", "inputs", "status")

_ROOTS = {
    "user": {
        "home": {"path": "${HOME}"},
        "config": {"path": "${XDG_CONFIG_HOME}"},
        "etc": {"path": "${XDG_CONFIG_HOME}"},
        "state": {"path": "${XDG_STATE_HOME}"},
        "var": {"path": "${XDG_STATE_HOME}"},
        "cache": {"path": "${XDG_CACHE_HOME}"},
        "data": {"path": "${XDG_DATA_HOME}"},
        "share": {"path": "${XDG_DATA_HOME}"},
        "bin": {"path": "${HOME}/.local/bin"},
        "log": {"path": "${XDG_STATE_HOME}/log"},
    },
    "system": {
        "config": {"path": "/etc"},
        "etc": {"path": "/etc"},
        "state": {"path": "/var/lib"},
        "var": {"path": "/var/lib"},
        "cache": {"path": "/var/cache"},
        "data": {"path": "/usr/share"},
        "share": {"path": "/usr/share"},
        "bin": {"path": "/usr/local/bin"},
        "log": {"path": "/var/log"},
    },
}


def _error(message):
    raise AnsibleFilterError("config_context_compile: {}".format(message))


def _mapping(value, label):
    if value is None:
        return {}
    if not isinstance(value, collections.abc.Mapping):
        _error("{} must be a mapping".format(label))
    return dict(value)


def _sequence(value, label):
    if not isinstance(value, collections.abc.Sequence) or isinstance(value, (str, bytes)):
        _error("{} must be a sequence".format(label))
    return list(value)


def _root(value, scope, label):
    if isinstance(value, str) and value in _ROOTS[scope]:
        return copy.deepcopy(_ROOTS[scope][value])
    return compile_path_selector(value, label, allow_relative=False)


def _under_etc(path, etc):
    if not isinstance(path, str) or not path.startswith("/"):
        return None
    normalized_path = posixpath.normpath(path)
    normalized_etc = posixpath.normpath(etc)
    try:
        if posixpath.commonpath([normalized_path, normalized_etc]) != normalized_etc:
            return None
    except ValueError:
        return None
    relative = posixpath.relpath(normalized_path, normalized_etc)
    return None if relative in ("", ".") else relative


def _derived_selector(path, etc, label):
    relative = _under_etc(path, etc)
    if relative is None:
        _error("{} is outside ETC; declare an explicit context binding".format(label))
    return {"relative": relative}


def _input_index(key, inputs, label):
    if isinstance(key, int) or (isinstance(key, str) and key.isdigit()):
        index = int(key)
        if index < 0 or index >= len(inputs):
            _error("{} references missing input {}".format(label, key))
        return index
    if isinstance(key, str):
        matches = [index for index, item in enumerate(inputs) if item.get("name") == key]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            _error("{} input name {!r} is ambiguous; use its index".format(label, key))
    _error("{} references unknown input {!r}".format(label, key))


def _config_declarations(value, available, label):
    if value is None:
        return {name: {} for name in available}
    if isinstance(value, collections.abc.Mapping):
        result = {}
        for name, declaration in value.items():
            if name not in available:
                _error("{} selects unknown config {!r}".format(label, name))
            result[name] = _mapping(declaration, "{}.{}".format(label, name))
        return result
    result = {}
    for name in _sequence(value, label):
        if not isinstance(name, str) or name not in available:
            _error("{} selects unknown config {!r}".format(label, name))
        if name in result:
            _error("{} selects config {!r} more than once".format(label, name))
        result[name] = {}
    return result


def _bin_name(record):
    if isinstance(record, str):
        return record
    if isinstance(record, collections.abc.Mapping):
        return record.get("dest", record.get("name"))
    return None


def _canonical_context(configs):
    bindings = {}
    for name, config in configs.items():
        bindings[name] = {
            "output": {"path": config["output"]},
            "inputs": [
                {"path": item.get("file", item.get("directory"))}
                for item in config.get("inputs", [])
            ],
        }
    return {
        "scope": "system",
        "canonical": True,
        "root": {"path": "/"},
        "configs": bindings,
        "install": "assemble",
        "dropins": "link",
    }


def _internalize_config_bins(records, config_names):
    """Move base CONFIG machinery internal and remove its legacy public leaves."""
    recipe_commands = {"config-{}.sh".format(name) for name in config_names}
    recipe_statuses = {"status-config-{}.sh".format(name) for name in config_names}
    result = []
    for raw in records:
        if not isinstance(raw, collections.abc.Mapping):
            result.append(raw)
            continue
        item = copy.deepcopy(dict(raw))
        name = item.get("dest", item.get("name"))
        if name in recipe_commands or name in recipe_statuses:
            continue
        if name == "config.sh":
            item.update({"name": "config/run.sh", "raw": True, "compose": False, "bypass": False})
            item.pop("dest", None)
        elif name == "config-toggle.sh":
            item.update({"name": "config/toggle.sh", "compose": False, "bypass": False})
            item.pop("dest", None)
        elif name == "config-processor.sh":
            item.update({"name": "config/processor.sh", "compose": False, "bypass": False})
            item.pop("dest", None)
        elif isinstance(name, str) and name.startswith("processors/"):
            item["name"] = "config/{}".format(name)
            item["bypass"] = False
            item.pop("dest", None)
            if isinstance(item.get("content"), str):
                item["content"] = item["content"].replace(
                    "$DIR/bin/config-processor.sh", "$DIR/bin/config/processor.sh"
                )
        elif isinstance(name, str) and name.startswith("internal/config/"):
            link = item.get("link")
            if isinstance(link, str) and link.startswith("processors/"):
                item["link"] = "config/{}".format(link)
        elif isinstance(item.get("content"), str):
            item["content"] = item["content"].replace(
                "$DIR/bin/config-toggle.sh", "$DIR/bin/config/toggle.sh"
            )
        result.append(item)
    return result


@accept_args_markers
def compile_config_contexts(compiled, contexts, etc, bins_dir=None, default_context="user", install_owner="config"):
    """Compile the v2 context schema and one fixed multicall command surface."""
    compiled = copy.deepcopy(_mapping(raw_copy_template_data(compiled), "compiled config"))
    contexts = _mapping(raw_copy_template_data(contexts), "CONFIG_CONTEXTS")
    if not isinstance(etc, str) or not etc.startswith("/"):
        _error("ETC must be an absolute path")
    if not isinstance(bins_dir, str) or not bins_dir.startswith("/"):
        _error("BINS_DIR must be an absolute path")

    spec = _mapping(compiled.get("spec"), "compiled config spec")
    configs = _mapping(spec.get("configs"), "compiled config spec.configs")
    if not configs and not contexts:
        return compiled
    if contexts and not configs:
        _error("CONFIG_CONTEXTS requires at least one compiled CONFIGS recipe")
    if not isinstance(install_owner, str) or not install_owner:
        _error("CONFIG_INSTALL_OWNER must be a non-empty domain name")

    bins = _internalize_config_bins(list(compiled.get("bins", [])), configs)
    occupied_bins = {name for name in (_bin_name(record) for record in bins) if name}
    runtime_bins = [
        ("config/command.ts", "../config/command.ts"),
        ("config/cli.ts", "../config/cli.ts"),
        ("config/assembly.ts", "../config/assembly.ts"),
        ("config/context.ts", "../config/context.ts"),
        ("config/inputs.ts", "../config/inputs.ts"),
        ("config/install.ts", "../config/install.ts"),
        ("config/invocation.ts", "../config/invocation.ts"),
        ("config/publication.ts", "../config/publication.ts"),
        ("config/report.ts", "../config/report.ts"),
        ("config/status.ts", "../config/status.ts"),
    ]
    for runtime_name, source in runtime_bins:
        if runtime_name in occupied_bins:
            _error("generated command collision: {}".format(runtime_name))
        bins.append({"name": runtime_name, "src": source, "raw": True, "compose": False, "basedir": False})
        occupied_bins.add(runtime_name)
    for record in links_runtime_bins(False):
        shared_name = record["name"]
        if shared_name in occupied_bins:
            _error("generated command collision: {}".format(shared_name))
        bins.append(record)
        occupied_bins.add(shared_name)

    normalized_contexts = {}
    for name, raw_context in contexts.items():
        label = "CONFIG_CONTEXTS.{}".format(name)
        if not isinstance(name, str) or not _ID.fullmatch(name):
            _error("context names must match {}".format(_ID.pattern))
        if name == _CANONICAL:
            _error("context name {!r} is reserved for canonical donor assembly".format(name))
        context = _mapping(raw_context, label)
        unknown = set(context) - {"scope", "root", "subpath", "configs", "install", "dropins"}
        if unknown:
            _error("{} has unknown settings: {}".format(label, ", ".join(sorted(unknown))))
        scope = context.get("scope")
        if scope not in _ROOTS:
            _error("{}.scope must be user or system".format(label))
        if "root" not in context:
            _error("{}.root is required".format(label))
        root = _root(context["root"], scope, "{}.root".format(label))
        install = context.get("install", "assemble")
        if install not in {"assemble", "copy", "link"}:
            _error("{}.install must be assemble, copy, or link".format(label))
        dropins = context.get("dropins", "link")
        if dropins not in {"copy", "link"}:
            _error("{}.dropins must be copy or link".format(label))
        subpath = context.get("subpath")
        if subpath is not None:
            subpath = relative_path(subpath, "{}.subpath".format(label))

        selected = _config_declarations(context.get("configs"), configs, "{}.configs".format(label))
        bindings = {}
        output_claims = {}
        for config_name, declaration in selected.items():
            config_label = "{}.configs.{}".format(label, config_name)
            unknown = set(declaration) - {"output", "inputs"}
            if unknown:
                _error("{} has unknown settings: {}".format(config_label, ", ".join(sorted(unknown))))
            config = _mapping(configs[config_name], "compiled config {}".format(config_name))
            inputs = list(config.get("inputs", []))
            input_overrides = _mapping(declaration.get("inputs"), "{}.inputs".format(config_label))
            overrides = {}
            for key, value in input_overrides.items():
                index = _input_index(key, inputs, "{}.inputs".format(config_label))
                if index in overrides:
                    _error("{}.inputs binds input {} more than once".format(config_label, index))
                overrides[index] = compile_path_selector(value, "{}.inputs.{}".format(config_label, key))

            bound_inputs = []
            for index, config_input in enumerate(inputs):
                if index in overrides:
                    bound_inputs.append(overrides[index])
                    continue
                source_path = config_input.get("file", config_input.get("directory"))
                bound_inputs.append(_derived_selector(source_path, etc, "{} input {} ({})".format(config_label, index, source_path)))

            output = compile_path_selector(declaration["output"], "{}.output".format(config_label)) if "output" in declaration else _derived_selector(config.get("output"), etc, "{} output ({})".format(config_label, config.get("output")))
            claim = json.dumps(output, sort_keys=True)
            prior = output_claims.get(claim)
            if prior is not None:
                _error("{} and {} have the same output binding".format(prior, config_label))
            output_claims[claim] = config_label
            bindings[config_name] = {"output": output, "inputs": bound_inputs}

        normalized = {"scope": scope, "root": root, "configs": bindings, "install": install, "dropins": dropins}
        if subpath is not None:
            normalized["subpath"] = subpath
        normalized_contexts[name] = normalized

    if normalized_contexts:
        if not isinstance(default_context, str) or default_context not in normalized_contexts:
            _error("CONFIG_CONTEXT must name a declared CONFIG_CONTEXTS context")
        selected_default = default_context
    else:
        selected_default = _CANONICAL
    normalized_contexts[_CANONICAL] = _canonical_context(configs)

    for action in _ACTIONS:
        command_name = "config-{}.sh".format(action)
        if command_name in occupied_bins:
            _error("generated command collision: {}".format(command_name))
        descriptor = {
            "name": command_name,
            "dest": command_name,
            "link": "config/command.ts",
            "compose": False,
            "basedir": False,
        }
        if action == "install" and normalized_contexts and selected_default != _CANONICAL and install_owner == "config":
            descriptor["action"] = "install"
            descriptor.pop("compose")
        bins.append(descriptor)
        occupied_bins.add(command_name)

    spec["version"] = 2
    spec["defaultContext"] = selected_default
    spec["contexts"] = normalized_contexts
    spec["installOwner"] = install_owner
    compiled["spec"] = spec
    compiled["bins"] = bins
    compiled["statuses"] = [{"name": "config-status.sh", "exit2": "error"}]
    legacy_processors = posixpath.join(bins_dir, "processors")
    dirs = [directory for directory in compiled.get("dirs", []) if directory != legacy_processors]
    for module_dir in [posixpath.join(bins_dir, "config"), posixpath.join(bins_dir, "config/processors")] + links_runtime_dirs(bins_dir):
        if module_dir not in dirs:
            dirs.append(module_dir)
    compiled["dirs"] = dirs
    return compiled


class FilterModule(object):
    def filters(self):
        return {"config_context_compile": compile_config_contexts}
