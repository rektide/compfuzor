"""Bind compiled CONFIGS recipes to reusable consumer contexts."""

from __future__ import annotations

import collections.abc
import copy
import json
import posixpath
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_ENV = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_RUNTIME_ROOT = re.compile(r"^\$\{(?:HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:/|$)")

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


def _relative(value, label):
    if not isinstance(value, str) or not value:
        _error("{} must be a non-empty relative path".format(label))
    normalized = posixpath.normpath(value)
    if value.startswith("/") or value.startswith("~") or value.startswith("$") or normalized in ("", ".") or normalized == ".." or normalized.startswith("../"):
        _error("{} must be a relative path contained by the context root".format(label))
    return normalized


def _runtime_path(value, label, allow_relative):
    if not isinstance(value, str) or not value:
        _error("{} must be a non-empty path".format(label))
    if value.startswith("/") or value == "~" or value.startswith("~/") or value.startswith("${"):
        runtime_root = _RUNTIME_ROOT.match(value)
        if "$" in value and (not runtime_root or "$" in value[runtime_root.end():]):
            _error("{} contains an unsupported runtime expression".format(label))
        return {"path": posixpath.normpath(value)}
    if "$" in value or "~" in value:
        _error("{} contains an unsupported runtime expression".format(label))
    if not allow_relative:
        _error("{} must be absolute or start with a HOME/XDG runtime root".format(label))
    return {"relative": _relative(value, label)}


def _selector(value, label, allow_relative=True):
    if isinstance(value, str):
        return _runtime_path(value, label, allow_relative)
    item = _mapping(value, label)
    unknown = set(item) - {"env", "default"}
    if unknown:
        _error("{} has unknown settings: {}".format(label, ", ".join(sorted(unknown))))
    env = item.get("env")
    if not isinstance(env, str) or not _ENV.fullmatch(env):
        _error("{}.env must name an environment variable".format(label))
    result = {"env": env}
    if "default" in item:
        result["default"] = _selector(item["default"], "{}.default".format(label), allow_relative)
    return result


def _root(value, scope, label):
    if isinstance(value, str) and value in _ROOTS[scope]:
        return copy.deepcopy(_ROOTS[scope][value])
    return _selector(value, label, allow_relative=False)


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


@accept_args_markers
def compile_config_contexts(compiled, contexts, etc, bins_dir=None):
    """Add normalized runtime contexts and their entry points to a config plan."""
    compiled = copy.deepcopy(_mapping(raw_copy_template_data(compiled), "compiled config"))
    contexts = _mapping(raw_copy_template_data(contexts), "CONFIG_CONTEXTS")
    if not contexts:
        return compiled
    if not isinstance(etc, str) or not etc.startswith("/"):
        _error("ETC must be an absolute path")
    if not isinstance(bins_dir, str) or not bins_dir.startswith("/"):
        _error("BINS_DIR must be an absolute path")

    spec = _mapping(compiled.get("spec"), "compiled config spec")
    configs = _mapping(spec.get("configs"), "compiled config spec.configs")
    bins = list(compiled.get("bins", []))
    occupied_bins = {name for name in (_bin_name(record) for record in bins) if name}
    runtime_name = "config-context.ts"
    if runtime_name in occupied_bins:
        _error("generated command collision: {}".format(runtime_name))
    bins.append({
        "name": runtime_name,
        "src": "../config-context.ts",
        "raw": True,
        "compose": False,
        "basedir": False,
    })
    occupied_bins.add(runtime_name)
    module_name = "config/context.ts"
    if module_name in occupied_bins:
        _error("generated command collision: {}".format(module_name))
    bins.append({
        "name": module_name,
        "src": "../config/context.ts",
        "raw": True,
        "compose": False,
        "basedir": False,
    })
    occupied_bins.add(module_name)

    normalized_contexts = {}
    for name, raw_context in contexts.items():
        label = "CONFIG_CONTEXTS.{}".format(name)
        if not isinstance(name, str) or not _ID.fullmatch(name):
            _error("context names must match {}".format(_ID.pattern))
        context = _mapping(raw_context, label)
        unknown = set(context) - {"scope", "root", "subpath", "configs"}
        if unknown:
            _error("{} has unknown settings: {}".format(label, ", ".join(sorted(unknown))))
        scope = context.get("scope")
        if scope not in _ROOTS:
            _error("{}.scope must be user or system".format(label))
        if "root" not in context:
            _error("{}.root is required".format(label))
        root = _root(context["root"], scope, "{}.root".format(label))
        subpath = context.get("subpath")
        if subpath is not None:
            subpath = _relative(subpath, "{}.subpath".format(label))

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
                overrides[index] = _selector(value, "{}.inputs.{}".format(config_label, key))

            bound_inputs = []
            for index, config_input in enumerate(inputs):
                if index in overrides:
                    bound_inputs.append(overrides[index])
                    continue
                source_path = config_input.get("file", config_input.get("directory"))
                bound_inputs.append(_derived_selector(source_path, etc, "{} input {} ({})".format(config_label, index, source_path)))

            if "output" in declaration:
                output = _selector(declaration["output"], "{}.output".format(config_label))
            else:
                output = _derived_selector(config.get("output"), etc, "{} output ({})".format(config_label, config.get("output")))
            claim = json.dumps(output, sort_keys=True)
            prior = output_claims.get(claim)
            if prior is not None:
                _error("{} and {} have the same output binding".format(prior, config_label))
            output_claims[claim] = config_label
            bindings[config_name] = {"output": output, "inputs": bound_inputs}

        command_name = "config-{}.sh".format(name)
        if command_name in occupied_bins:
            _error("generated command collision: {}".format(command_name))
        occupied_bins.add(command_name)
        bins.append({
            "name": command_name,
            "basedir": False,
            "helpers": False,
            "compose": False,
            "content": 'exec "$(dirname "$(readlink -f "$0")")/config-context.ts" --context {} "$@"'.format(name),
        })
        normalized = {"scope": scope, "root": root, "configs": bindings}
        if subpath is not None:
            normalized["subpath"] = subpath
        normalized_contexts[name] = normalized

    spec["contexts"] = normalized_contexts
    compiled["spec"] = spec
    compiled["bins"] = bins
    dirs = list(compiled.get("dirs", []))
    module_dir = posixpath.join(bins_dir, "config")
    if module_dir not in dirs:
        dirs.append(module_dir)
    compiled["dirs"] = dirs
    return compiled


class FilterModule(object):
    def filters(self):
        return {"config_context_compile": compile_config_contexts}
