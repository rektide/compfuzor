"""Package independent complete CONFIG definitions around the shared engine."""

from __future__ import annotations

import copy
import json
import posixpath
import shlex

from ansible.template import accept_args_markers

from config_compile import compile_config, config_runtime_packages, _mapping, _error, _ID
from config_context_compile import compile_config_contexts, _ACTIONS
from template_data import raw_copy_template_data


@accept_args_markers
def compile_definitions(definitions, etc, bins_dir, legacy=None, defaults=None, default=None):
    definitions = _mapping(raw_copy_template_data(definitions), "CONFIG_DEFINITIONS")
    defaults = _mapping(raw_copy_template_data(defaults), "CONFIG defaults")
    if legacy is not None and _mapping(legacy, "CONFIGS"):
        if "default" in definitions:
            _error("CONFIGS and CONFIG_DEFINITIONS.default cannot both be declared")
        definitions["default"] = {"configs": raw_copy_template_data(legacy), **defaults}
    if not definitions:
        return {"instances": {}, "contrib": {"DIRS": [], "ETC_FILES": [], "BINS": [], "STATUSES": [], "PKGS": []}}
    if any(not isinstance(identity, str) or not _ID.fullmatch(identity) for identity in definitions):
        _error("CONFIG_DEFINITIONS names must be stable identifiers")
    selected_default = default or ("default" if "default" in definitions else sorted(definitions)[0])
    if selected_default not in definitions:
        _error("CONFIG_DEFAULT must select a complete CONFIG definition")
    instances = {}
    contrib = {"DIRS": [], "ETC_FILES": [], "BINS": [], "STATUSES": [], "PKGS": config_runtime_packages()}
    claimed_outputs = {}
    single_legacy = bool(legacy) and len(definitions) == 1
    if not single_legacy:
        command_claims = {"config-{}.sh".format(action): "the fixed default command" for action in _ACTIONS}
        for identity in sorted(definitions):
            for action in _ACTIONS:
                command = "config-{}-{}.sh".format(identity, action)
                if command in command_claims:
                    _error("CONFIG definition {}/{} command {} collides with {}; choose an unambiguous definition name".format(identity, action, command, command_claims[command]))
                command_claims[command] = identity + "/" + action
    for identity in sorted(definitions):
        if not isinstance(identity, str) or not _ID.fullmatch(identity):
            _error("CONFIG_DEFINITIONS names must be stable identifiers")
        declaration = _mapping(definitions[identity], "CONFIG_DEFINITIONS." + identity)
        unknown = set(declaration) - {"configs", "contexts", "context", "install_owner", "disabled_suffix", "transaction_validate", "action_contexts", "audiences", "etc"}
        if unknown:
            _error("CONFIG_DEFINITIONS.{}: unknown settings {}".format(identity, sorted(unknown)))
        if not declaration.get("configs"):
            _error("CONFIG_DEFINITIONS.{} requires at least one configs recipe".format(identity))
        bound_identity = identity
        material = declaration.get("etc", etc)
        compiled = compile_config(declaration["configs"], material, bins_dir,
            declaration.get("disabled_suffix", ".disabled"), declaration.get("transaction_validate"), None if single_legacy else bound_identity)
        compiled = compile_config_contexts(compiled, declaration.get("contexts", {}), material, bins_dir,
            declaration.get("context", "user"), declaration.get("install_owner", "config"),
            declaration.get("audiences", defaults.get("audiences")), declaration.get("action_contexts"), None if single_legacy else bound_identity)
        spec = compiled["spec"]
        if any(recipe["processor"] in ("env", "env-export", "env-zsh") for recipe in spec["configs"].values()):
            if "python3" not in contrib["PKGS"]:
                contrib["PKGS"].append("python3")
        spec["identity"] = identity
        spec["deploymentRoot"] = posixpath.dirname(bins_dir)
        spec_name = "config/{}/spec.json".format(identity)
        instances[identity] = {"spec": spec, "path": "etc/" + spec_name}
        for name, recipe in spec["configs"].items():
            output = recipe["output"]
            if output in claimed_outputs:
                _error("CONFIG definitions {} and {}/{} claim output {}".format(claimed_outputs[output], identity, name, output))
            claimed_outputs[output] = identity + "/" + name
        for context_name, context in spec.get("contexts", {}).items():
            if context.get("canonical"):
                continue
            for recipe_name, binding in context["configs"].items():
                selector = binding["output"]
                root = context["root"].get("path", "")
                if "path" in selector and selector["path"].startswith("/"):
                    claim = posixpath.normpath(selector["path"])
                elif "relative" in selector and root.startswith("/"):
                    claim = posixpath.normpath(posixpath.join(root, context.get("subpath", ""), selector["relative"]))
                else:
                    claim = "selector:" + json.dumps([context["scope"], context["root"], context.get("subpath"), selector], sort_keys=True)
                prior = claimed_outputs.get(claim)
                if prior and not prior.startswith(identity + "/"):
                    _error("CONFIG definitions {} and {}/{}/{} claim the same context output".format(prior, identity, context_name, recipe_name))
                claimed_outputs[claim] = identity + "/" + context_name + "/" + recipe_name
        contrib["ETC_FILES"].append({"name": spec_name, "json": spec})
        for family, key in (("DIRS", "dirs"), ("BINS", "bins"), ("STATUSES", "statuses")):
            for record in compiled[key]:
                record = copy.deepcopy(record)
                # The stock runner is emitted once; canonical builds bind each spec.
                if family == "BINS" and record.get("name") == "config/run.sh":
                    record["run"] = False
                if record not in contrib[family]:
                    contrib[family].append(record)
        contrib["DIRS"].append(posixpath.join(etc, "config", identity))
        contrib["BINS"].append({"name": "config/build-{}.sh".format(identity), "helpers": False,
            "basedir": False, "compose": False, "bypass": False, "run": True, "requires_fs": True,
            "content": 'exec {} config --action assemble --context canonical --spec {} "$@"'.format(
                shlex.quote(posixpath.join(bins_dir, "compfuzor-runtime.mjs")), shlex.quote(posixpath.join(etc, spec_name)))})
    contrib["ETC_FILES"].append({"name": "config.spec.json", "json": instances[selected_default]["spec"]})
    # Existing default entrypoints are exposures of the selected definition.
    from runtime_bundles import runtime_alias_bin
    if not single_legacy:
        contrib["BINS"].extend(runtime_alias_bin("config-{}.sh".format(action)) for action in _ACTIONS)
    index = {"version": 1, "default": selected_default, "definitions": {key: {"spec": value["path"]} for key, value in instances.items()}}
    contrib["DIRS"].append(posixpath.join(etc, "config"))
    contrib["ETC_FILES"].append({"name": "config/instances.json", "json": index})
    return {"requested": True, "instances": instances, "default": selected_default,
        "spec": instances[selected_default]["spec"], "contrib": contrib}


class FilterModule(object):
    def filters(self):
        return {"config_definitions_compile": compile_definitions, "config_definitions_publish": publish_definitions}


@accept_args_markers
def publish_definitions(subsystems, compiled):
    subsystems = _mapping(raw_copy_template_data(subsystems), "SUBSYSTEM")
    subsystems["config"] = raw_copy_template_data(compiled)
    return subsystems
