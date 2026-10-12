"""Normalize explicit application ENV and generate an independent CONFIG."""

from __future__ import annotations

import json
import posixpath
import re
import shlex
from collections.abc import Mapping, Sequence

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers
from template_data import raw_copy_template_data


_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def error(message):
    raise AnsibleFilterError("env_compile: " + message)


def values(mapping, names, variables):
    if mapping is None or isinstance(mapping, bool):
        mapping = {}
    if not isinstance(mapping, Mapping):
        error("ENV must be a mapping or boolean")
    result = {}
    for key in names:
        if not isinstance(key, str):
            error("ENV_LIST entries must be variable names")
        if key in variables:
            result[key] = variables[key]
        elif key.upper() in variables:
            result[key] = variables[key.upper()]
        else:
            error("missing authored ENV_LIST variable " + key)
    result.update(mapping)
    normalized = {}
    for key, value in result.items():
        if not isinstance(key, str):
            error("environment variable names must be strings")
        authored_key = key
        key = key.upper()
        if not _KEY.fullmatch(key):
            error("invalid environment variable name " + key)
        if value is None:
            continue
        if value is True:
            if authored_key not in variables and key not in variables:
                error("missing ENV lookup variable " + key)
            value = variables[authored_key] if authored_key in variables else variables[key]
        if isinstance(value, Sequence) and not isinstance(value, str):
            value = " ".join(str(part) for part in value)
        elif isinstance(value, Mapping):
            error(key + ": mapping values are not supported")
        value = str(value)
        if any(ord(char) < 32 or ord(char) == 127 for char in value):
            error(key + ": multiline/control characters are not supported")
        normalized[key] = value
    return normalized


def fragment(mapping):
    return "".join(key + "=" + json.dumps(value, ensure_ascii=False) + "\n" for key, value in mapping.items())


@accept_args_markers
def compile_env(declaration, env, env_list, priority, priority_list, variables, contributions, etc, directory):
    declaration = raw_copy_template_data(declaration)
    if declaration is True:
        declaration = {}
    if not isinstance(declaration, Mapping):
        error("ENV_CONFIG must be true or a mapping")
    if set(declaration) - {"name", "contexts", "context", "install_owner", "projections"}:
        error("unknown ENV_CONFIG setting")
    variables = {key: value for key, value in raw_copy_template_data(variables).items() if value != '__ENV_CONFIG_UNSET_COMPFUZOR__'}
    ordinary = values(raw_copy_template_data(env), raw_copy_template_data(env_list), variables)
    prio = values(raw_copy_template_data(priority), raw_copy_template_data(priority_list), variables)
    effective = {**ordinary, **prio}
    contributions = raw_copy_template_data(contributions)
    files = [{"name": "env.d/00-local.env", "content": fragment(ordinary), "mode": "0600"},
             {"name": "env.d/99-local-priority.env", "content": fragment(prio), "mode": "0600"}]
    for filename, mapping in contributions.items():
        if not isinstance(filename, str) or posixpath.basename(filename) != filename or not filename.endswith(".env") or filename in ("00-local.env", "99-local-priority.env"):
            error("ENV_CONTRIBUTIONS requires distinct native .env filenames")
        files.append({"name": "env.d/" + filename, "content": fragment(values(mapping, [], variables)), "mode": "0600"})
    configs = {}
    for name, output, processor in (("env", posixpath.join(directory, "env"), "env"), ("export", posixpath.join(directory, "env.export"), "env-export")):
        configs[output] = {"name": name, "processor": processor,
            "inputs": [{"glob": "env.d/*.env", "name": name}, {"file": "env.d/99-local-priority.env"}]}
    for name, projection in declaration.get("projections", {}).items():
        if not isinstance(name, str) or posixpath.basename(name) != name or name in ("", ".", ".."):
            error("ENV projection names must be native filenames")
        if not isinstance(projection, Mapping) or set(projection) != {"files", "format"} or projection["format"] not in ("env", "env-export", "env-zsh"):
            error("ENV_CONFIG.projections requires files and format (env/env-export/env-zsh)")
        selected = projection["files"]
        if not isinstance(selected, list) or any(not isinstance(path, str) or posixpath.basename(path) != path or not path.endswith(".env") for path in selected):
            error("ENV projection files must name exact env.d contributions")
        configs["env-projections/" + name] = {"processor": projection["format"], "inputs": [{"file": "env.d/" + path} for path in selected]}
    definition = {"configs": configs, **{key: raw_copy_template_data(declaration[key]) for key in ("contexts", "context", "install_owner") if key in declaration}}
    context = {key: str(variables.get(key, "")) for key in ("NAME", "TYPE", "INSTANCE", "REPO", "BUILD_DIR", "GLOBAL_BINS_DIR")}
    context["DIR"] = directory
    runtime_context = "".join("export " + key + "=" + shlex.quote(value) + "\n" for key, value in context.items())
    return {"name": declaration.get("name", "env"), "definition": definition, "files": files,
        "dirs": ["env.d", "env-projections"], "effective": effective,
        "context_file": {"name": "env.context", "content": runtime_context, "mode": "0600"}}


class FilterModule(object):
    def filters(self):
        return {"env_config_compile": compile_env, "env_config_add": add_env_definition, "env_config_names": lookup_names}


@accept_args_markers
def lookup_names(env, priority, contributions, ordinary_list, priority_list):
    mappings = [raw_copy_template_data(env), raw_copy_template_data(priority)]
    mappings.extend(raw_copy_template_data(contributions).values())
    names = list(raw_copy_template_data(ordinary_list)) + list(raw_copy_template_data(priority_list))
    for mapping in mappings:
        if isinstance(mapping, Mapping):
            names.extend(mapping.keys())
    names.extend(("DIR", "NAME", "TYPE", "INSTANCE", "REPO", "BUILD_DIR", "GLOBAL_BINS_DIR"))
    if any(not isinstance(name, str) for name in names):
        error("environment variable names must be strings")
    return list(dict.fromkeys(names))


@accept_args_markers
def add_env_definition(definitions, compiled):
    definitions = dict(raw_copy_template_data(definitions))
    compiled = raw_copy_template_data(compiled)
    if compiled["name"] in definitions:
        error("ENV_CONFIG owns definition " + compiled["name"] + "; use its settings rather than also declaring CONFIG_DEFINITIONS with that name")
    definitions[compiled["name"]] = compiled["definition"]
    return definitions
