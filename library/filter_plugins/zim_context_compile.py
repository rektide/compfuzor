"""Compile Zim activation contexts over existing CONFIG_CONTEXTS bindings."""

from __future__ import annotations

import collections.abc
import copy
import posixpath
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from config_selectors import compile_path_selector
from template_data import raw_copy_template_data


_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_RESERVED_CONTEXTS = {"context", "donor"}


def _error(message):
    raise AnsibleFilterError("zim_context_compile: {}".format(message))


def _mapping(value, label):
    if value is None:
        return {}
    if not isinstance(value, collections.abc.Mapping):
        _error("{} must be a mapping".format(label))
    return dict(value)


@accept_args_markers
def compile_zim_contexts(contexts, config_spec, default_context, etc, directory, bins_dir, name, existing_bins=None):
    """Normalize ZIM_CONTEXTS and emit one generic install/status runtime."""
    contexts = _mapping(raw_copy_template_data(contexts), "ZIM_CONTEXTS")
    config_spec = _mapping(raw_copy_template_data(config_spec), "config spec")
    config_contexts = _mapping(config_spec.get("contexts"), "config spec.contexts")
    if not contexts:
        _error("ZIM_CONTEXTS must declare at least one activation context")
    if not isinstance(default_context, str) or default_context not in contexts:
        _error("ZIM_CONTEXT must name a declared ZIM_CONTEXTS context")
    for value, label in ((etc, "ETC"), (directory, "DIR"), (bins_dir, "BINS_DIR")):
        if not isinstance(value, str) or not value.startswith("/"):
            _error("{} must be an absolute path".format(label))
    if not isinstance(name, str) or not name:
        _error("NAME must be a non-empty string")

    normalized = {}
    for context_name, raw in contexts.items():
        label = "ZIM_CONTEXTS.{}".format(context_name)
        if not isinstance(context_name, str) or not _ID.fullmatch(context_name):
            _error("Zim context names must match {}".format(_ID.pattern))
        if context_name in _RESERVED_CONTEXTS:
            _error(
                "Zim context {!r} would collide with the install-zim-{}.sh role command".format(
                    context_name, context_name
                )
            )
        item = _mapping(raw, label)
        unknown = set(item) - {"config", "loader_root", "zimrc_home", "zimenv_home", "registry"}
        if unknown:
            _error("{} has unknown settings: {}".format(label, ", ".join(sorted(unknown))))
        config_name = item.get("config", context_name)
        if not isinstance(config_name, str) or config_name not in config_contexts:
            _error("{}.config must name a declared CONFIG_CONTEXTS context".format(label))
        config_context = _mapping(config_contexts[config_name], "config context {}".format(config_name))
        scope = config_context.get("scope")
        if scope not in {"user", "system"}:
            _error("{}.config has an invalid scope".format(label))
        selected_configs = _mapping(config_context.get("configs"), "config context {}.configs".format(config_name))
        for channel in ("zimrc", "zimenv"):
            if channel not in selected_configs:
                _error("{}.config must expose {}".format(label, channel))

        if scope == "user":
            defaults = {
                "loader_root": {"env": "ZDOTDIR", "default": "${HOME}"},
                "zimrc_home": {"env": "ZIM_HOME", "default": "${HOME}/.cache/zim"},
                "zimenv_home": {"env": "ZIM_ENV_HOME", "default": "${HOME}/.cache/zim-env"},
                "registry": {"env": "ZIM_CONFIG_LINK", "default": "${XDG_CONFIG_HOME}/zsh/zimfw.conf"},
            }
        else:
            defaults = {}
            missing = [field for field in ("loader_root", "zimrc_home", "zimenv_home", "registry") if field not in item]
            if missing:
                _error("{} system context requires: {}".format(label, ", ".join(missing)))

        resolved = {"config": config_name, "scope": scope}
        for field in ("loader_root", "zimrc_home", "zimenv_home", "registry"):
            resolved[field] = compile_path_selector(item.get(field, defaults.get(field)), "{}.{}".format(label, field), allow_relative=False)
        normalized[context_name] = resolved

    occupied = set()
    for record in list(raw_copy_template_data(existing_bins) or []):
        if isinstance(record, collections.abc.Mapping):
            occupied.add(record.get("dest", record.get("name")))
        elif isinstance(record, str):
            occupied.add(record)
    generated_names = {
        "zim/install.ts",
        "install-zim.sh",
        "status-zim.sh",
        "install-zim-context.sh",
        "install-zim-donor.sh",
    }
    collision = sorted(generated_names & occupied)
    if collision:
        _error("generated command collision: {}".format(", ".join(collision)))

    bins = [
        {"name": "zim/install.ts", "src": "../zim/install.ts", "raw": True, "compose": False, "basedir": False},
        {"name": "install-zim.sh", "src": "../install-zim.sh", "raw": True, "basedir": False, "action": "install"},
        {
            "name": "status-zim.sh",
            "helpers": False,
            "basedir": False,
            "compose": False,
            "content": 'exec "$(dirname "$(readlink -f "$0")")/zim/install.ts" status "$@"',
        },
    ]
    spec = {
        "version": 2,
        "defaultContext": default_context,
        "contexts": normalized,
        "canonical": {
            "zimrc": posixpath.join(etc, "zimrc"),
            "zimenv": posixpath.join(etc, "zimenv"),
            "zimrcLegacy": [
                posixpath.join(etc, "zimrc"),
                posixpath.join(directory, "etc", "zimrc"),
            ],
            "zimenvLegacy": [
                posixpath.join(etc, "zimenv"),
                posixpath.join(directory, "etc", "zimenv"),
            ],
            "zimrcLoaderTemplate": posixpath.join(directory, "etc", "zimrc.zsh"),
            "zimenvLoaderTemplate": posixpath.join(directory, "etc", "zimenv.zsh"),
            "controller": posixpath.join(directory, "src", "zimfw.zsh"),
            "emergencyModule": posixpath.join(etc, "zim-modules", "emergency", "init.zsh"),
            "registry": posixpath.join(etc, "zimrc"),
            "blockPrefix": name,
        },
    }
    return {
        "spec": copy.deepcopy(spec),
        "bins": bins,
        "dirs": [posixpath.join(bins_dir, "zim")],
        "etc_files": [{"name": "zim.spec.json", "json": spec}],
        "statuses": [{"name": "status-zim.sh", "exit2": "error"}],
    }


class FilterModule(object):
    def filters(self):
        return {"zim_context_compile": compile_zim_contexts}
