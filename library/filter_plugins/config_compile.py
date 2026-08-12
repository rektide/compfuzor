"""Compile filename-keyed config declarations into runtime artifacts."""

from __future__ import annotations

import collections.abc
import posixpath
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_PROCESSORS = {"concat", "json-deep-merge", "block-in-file"}
_PLACEMENTS = ("before", "after")


def _error(message):
    raise AnsibleFilterError("config_compile: {}".format(message))


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


def _path(base, value, label):
    if not isinstance(value, str) or not value:
        _error("{} must be a non-empty path".format(label))
    if value.startswith("/") or value.startswith("~"):
        return posixpath.normpath(value)
    if not isinstance(base, str) or not base:
        _error("{} requires a base directory".format(label))
    return posixpath.normpath(posixpath.join(base, value))


def _name_from_output(output_key):
    basename = posixpath.basename(output_key)
    name = basename.rsplit(".", 1)[0] if "." in basename else basename
    if not _ID.fullmatch(name):
        _error("derived config name {!r} requires an explicit name".format(name))
    return name


def _glob_parts(path, label):
    directory, pattern = posixpath.split(path)
    if not directory or not pattern or "/" in pattern:
        _error("{} must have a concrete directory and filename pattern".format(label))
    return directory, pattern


def _block(value, label, inherited=None):
    block = dict(inherited or {})
    local = _mapping(value, label)
    unknown = set(local) - set(_PLACEMENTS) - {"remove_match"}
    if unknown:
        _error("{} has unknown settings: {}".format(label, ", ".join(sorted(unknown))))
    for key, setting in local.items():
        if key == "remove_match":
            patterns = _sequence(setting, "{}.remove_match".format(label))
            if any(not isinstance(pattern, str) or not pattern for pattern in patterns):
                _error("{}.remove_match entries must be non-empty strings".format(label))
            block[key] = patterns
        elif not isinstance(setting, str) or not setting:
            _error("{}.{} must be a non-empty string".format(label, key))
        else:
            block[key] = setting
    placements = [key for key in _PLACEMENTS if key in block]
    if len(placements) > 1:
        _error("{} has conflicting placement settings: {}".format(label, ", ".join(placements)))
    return block


@accept_args_markers
def compile_config(configs, etc, bins_dir=None, disabled_suffix=".disabled"):
    """Normalize CONFIGS and emit config subsystem contributions."""
    configs = _mapping(raw_copy_template_data(configs), "CONFIGS")
    normalized = {}
    remotes = {}
    mutable_inputs = {}
    dirs = []
    bins = []
    statuses = []

    if configs:
        bins.extend([
            {"name": "config.sh", "src": "../config-run.sh", "basedir": False, "run": True, "requires_fs": True},
            {"name": "config-toggle.sh", "src": "../config-toggle.sh", "basedir": False},
            {"name": "config-processor.sh", "src": "../config-processor.sh", "basedir": False},
        ])
        for processor in sorted(_PROCESSORS):
            bins.append({
                "name": "processors/{}".format(processor),
                "basedir": False,
                "helpers": ["env"],
                "content": 'exec "$DIR/bin/config-processor.sh" {} "$@"'.format(processor),
            })

    output_owners = {}
    for output_key, raw in configs.items():
        if not isinstance(output_key, str) or not output_key:
            _error("CONFIGS keys must be output paths")
        raw = _mapping(raw, "CONFIGS.{}".format(output_key))
        base = raw.get("dir", etc)
        output = _path(base, output_key, "CONFIGS.{} output".format(output_key))
        name = raw.get("name", _name_from_output(output_key))
        if not isinstance(name, str) or not _ID.fullmatch(name):
            _error("CONFIGS.{}.name must match {}".format(output_key, _ID.pattern))
        if name in normalized:
            _error("duplicate config name {!r}".format(name))
        if output in output_owners:
            _error("output {!r} is claimed by {} and {}".format(output, output_owners[output], name))
        output_owners[output] = name

        processor = raw.get("processor")
        if processor not in _PROCESSORS:
            _error("unsupported processor {!r}".format(processor))
        validate = raw.get("validate")
        if validate is not None and (not isinstance(validate, str) or not validate):
            _error("CONFIGS.{}.validate must be a non-empty command".format(output_key))
        block = None
        if processor == "block-in-file":
            block = _block(raw.get("block"), "CONFIGS.{}.block".format(output_key))
            block["namespace"] = name
        elif "block" in raw:
            _error("block settings require the block-in-file processor")

        config_suffix = raw.get("disabled_suffix", disabled_suffix)
        if config_suffix is False:
            config_suffix = None
        if config_suffix is not None and (not isinstance(config_suffix, str) or not config_suffix.startswith(".")):
            _error("CONFIGS.{}.disabled_suffix must start with '.' or be false".format(output_key))

        inputs_raw = raw.get("inputs")
        if inputs_raw is None:
            extension = posixpath.basename(output_key).rsplit(".", 1)[-1] if "." in posixpath.basename(output_key) else "*"
            inputs_raw = [{"glob": "{}.d/*.{}".format(output_key, extension)}]
        inputs = []
        glob_indices = []
        for index, item in enumerate(_sequence(inputs_raw, "CONFIGS.{}.inputs".format(output_key))):
            if isinstance(item, str):
                item = {"file": item}
            item = _mapping(item, "CONFIGS.{}.inputs[{}]".format(output_key, index))
            typed = [(key, value) for key, value in item.items() if key in ("file", "glob")]
            if len(typed) != 1:
                _error("config inputs require exactly one file or glob")
            kind, value = typed[0]
            input_base = item.get("dir", base)
            if kind == "file":
                unknown = set(item) - {"file", "dir", "block"}
                if unknown:
                    _error("file input has unknown settings: {}".format(", ".join(sorted(unknown))))
                normalized_input = {"file": _path(input_base, value, "config file input")}
            else:
                unknown = set(item) - {"glob", "dir", "name", "remote", "disabled_suffix", "block"}
                if unknown:
                    _error("glob input has unknown settings: {}".format(", ".join(sorted(unknown))))
                glob_path = _path(input_base, value, "config glob input")
                directory, pattern = _glob_parts(glob_path, "config glob input")
                input_name = item.get("name", posixpath.basename(directory))
                if not isinstance(input_name, str) or not _ID.fullmatch(input_name):
                    _error("glob input name {!r} requires an explicit valid name".format(input_name))
                suffix = item.get("disabled_suffix", config_suffix)
                if suffix is False:
                    suffix = None
                if suffix is not None and (not isinstance(suffix, str) or not suffix.startswith(".")):
                    _error("glob disabled_suffix must start with '.' or be false")
                normalized_input = {
                    "glob": glob_path,
                    "directory": directory,
                    "pattern": pattern,
                    "name": input_name,
                    "disabled_suffix": suffix,
                    "remote": bool(item.get("remote", False)),
                }
                glob_indices.append(index)
            if processor == "block-in-file":
                normalized_input["block"] = _block(item.get("block"), "CONFIGS.{}.inputs[{}].block".format(output_key, index), block)
            elif "block" in item:
                _error("input block settings require the block-in-file processor")
            inputs.append(normalized_input)

        if raw.get("remote", False):
            if not glob_indices:
                _error("CONFIGS.{}.remote requires a glob input".format(output_key))
            inputs[glob_indices[0]]["remote"] = True

        for index in glob_indices:
            item = inputs[index]
            target_name = item["name"]
            if item["disabled_suffix"]:
                owner = mutable_inputs.get(target_name)
                if owner is not None:
                    _error("mutable glob name {!r} is shared by {} and {}".format(target_name, owner, name))
                mutable_inputs[target_name] = name
                for action in ("disable", "enable"):
                    bins.append({
                        "name": "{}-{}.sh".format(action, target_name),
                        "basedir": False,
                        "content": 'exec "$DIR/bin/config-toggle.sh" {} {} {} "$@"'.format(action, name, target_name),
                    })
            if item["remote"]:
                if target_name in remotes:
                    _error("remote target {!r} is declared more than once".format(target_name))
                remotes[target_name] = {
                    "config": name,
                    "directory": item["directory"],
                    "pattern": item["pattern"],
                    "disabled_suffix": item["disabled_suffix"],
                }

        normalized[name] = {
            "output": output,
            "processor": processor,
            "inputs": inputs,
            "validate": validate,
            "apply": bool(raw.get("apply", True)),
        }
        if block is not None:
            normalized[name]["block"] = block
        output_dir = posixpath.dirname(output)
        if output_dir and output_dir not in dirs:
            dirs.append(output_dir)
        leaf = "internal/config/{}".format(name)
        bins.append({"name": leaf, "dest": leaf, "link": "processors/{}".format(processor)})
        bins.append({"name": "config-{}.sh".format(name), "basedir": False, "content": 'exec "$DIR/bin/config.sh" {} "$@"'.format(name)})
        status = "status-config-{}.sh".format(name)
        bins.append({"name": status, "basedir": False, "content": 'exec "$DIR/bin/config-{}.sh" --check "$@"'.format(name)})
        statuses.append(status)

    if configs and bins_dir is not None:
        for path in ("processors", "internal/config"):
            directory = _path(bins_dir, path, "config bin directory")
            if directory not in dirs:
                dirs.append(directory)

    return {
        "dirs": dirs,
        "spec": {"configs": normalized, "remotes": remotes},
        "bins": bins,
        "statuses": statuses,
    }


@accept_args_markers
def publish_config(subsystems, compiled):
    """Publish compiled config state without templating unrelated subsystems."""
    subsystems = _mapping(raw_copy_template_data(subsystems), "SUBSYSTEM")
    compiled = _mapping(raw_copy_template_data(compiled), "compiled config")
    current = _mapping(subsystems.get("config"), "SUBSYSTEM.config")
    spec = _mapping(compiled.get("spec"), "compiled config spec")
    contrib = {
        "DIRS": list(compiled.get("dirs", [])),
        "ETC_FILES": [{"name": "config.spec.json", "json": spec}],
        "BINS": list(compiled.get("bins", [])),
        "STATUSES": list(compiled.get("statuses", [])),
        "PKGS": ["jq"],
    }
    current.update({"requested": True, "spec": spec, "contrib": contrib})
    subsystems["config"] = current
    return subsystems


class FilterModule(object):
    def filters(self):
        return {"config_compile": compile_config, "config_publish": publish_config}
