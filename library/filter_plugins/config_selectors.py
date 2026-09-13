"""Compile portable HOME/XDG-aware runtime path selectors."""

from __future__ import annotations

import collections.abc
import posixpath
import re

from ansible.errors import AnsibleFilterError


_ENV = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_RUNTIME_ROOT = re.compile(r"^\$\{(?:HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:/|$)")


def _error(message):
    raise AnsibleFilterError("config_selectors: {}".format(message))


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


def relative_path(value, label):
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
    return {"relative": relative_path(value, label)}


def compile_path_selector(value, label, allow_relative=True):
    """Compile a literal or env/default selector into its durable shape."""
    if isinstance(value, str):
        return _runtime_path(value, label, allow_relative)
    item = _mapping(value, label)
    unknown = set(item) - {"env", "default", "ignore"}
    if unknown:
        _error("{} has unknown settings: {}".format(label, ", ".join(sorted(unknown))))
    env = item.get("env")
    if not isinstance(env, str) or not _ENV.fullmatch(env):
        _error("{}.env must name an environment variable".format(label))
    result = {"env": env}
    if "ignore" in item:
        ignored = _sequence(item["ignore"], "{}.ignore".format(label))
        if any(not isinstance(entry, str) or not entry for entry in ignored):
            _error("{}.ignore entries must be non-empty strings".format(label))
        result["ignore"] = ignored
    if "default" in item:
        result["default"] = compile_path_selector(item["default"], "{}.default".format(label), allow_relative)
    return result


class FilterModule(object):
    def filters(self):
        return {"config_path_selector": compile_path_selector}
