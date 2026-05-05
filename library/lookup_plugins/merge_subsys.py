from __future__ import annotations

DOCUMENTATION = """
    name: merge_subsys
    author: compfuzor
    short_description: Merge one subsystem contrib artifact into its global artifact
    description:
      - Reads C(SUBSYSTEM.<id>.contrib.<contrib>) and the matching current global artifact.
      - Dispatches to the merge helpers in C(library/filter_plugins/merge.py).
      - Reads variables through raw-copy helpers so tagged template strings are not rendered during merge.
    options:
      _terms:
        description:
          - Positional terms are not supported.
          - Use C(id=...) instead.
        required: false
      id:
        description:
          - Subsystem id to read from C(SUBSYSTEM).
      fallback_id:
        description:
          - Subsystem id used when C(id) is absent or empty.
      contrib:
        description:
          - Artifact key under C(contrib), such as C(BINS), C(ENV), C(ETC_FILES), C(PKGS), C(ENV_LIST), or C(LINKS).
      path:
        description:
          - Optional dotted path override for the incoming subsystem payload.
          - Defaults to C(contrib.<contrib>).
      current:
        description:
          - Optional current/global variable name.
          - Defaults to the C(contrib) value.
      strategy:
        description:
          - Optional merge strategy override.
      default:
        description:
          - Optional missing incoming payload default.
      active:
        description:
          - When truthy, merge only when the subsystem active path is truthy.
      active_path:
        description:
          - Dotted path used for active gating. Defaults to C(active).
      current_wins:
        description:
          - Dict artifacts only. When truthy, current/global values override incoming subsystem values.
      current_first:
        description:
          - List artifacts only. When truthy, current/global list payload is merged before incoming subsystem payload.
      get:
        description:
          - Optional dotted path to extract from the merged result.
"""

EXAMPLES = """
- name: Merge python BINS
  ansible.builtin.set_fact:
    BINS: "{{ lookup('merge_subsys', id='python', contrib='BINS') }}"

- name: Merge kernel package contributions
  ansible.builtin.set_fact:
    PKGS: "{{ lookup('merge_subsys', id='kernel_all', contrib='PKGS') }}"

- name: Merge python environment
  ansible.builtin.set_fact:
    ENV: "{{ lookup('merge_subsys', id='python', contrib='ENV') }}"
"""

RETURN = """
_value:
  description:
    - Merged artifact value.
  type: raw
"""

import os
import sys

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.plugins.test.core import wrapped_test_undefined

_FILTER_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "filter_plugins")
)
if _FILTER_DIR not in sys.path:
    sys.path.insert(0, _FILTER_DIR)

from get import get_path  # noqa: E402
from merge import (  # noqa: E402
    _dict_get_raw,
    _raw_copy_template_data,
    _truthy,
    merge_dict,
    merge_list,
)


ARTIFACT_DEFAULTS = {
    "BINS": {
        "kind": "list",
        "strategy": "bins_generated",
        "default": [],
        "current_first": True,
    },
    "ETC_FILES": {
        "kind": "list",
        "strategy": "append",
        "default": [],
        "current_first": True,
    },
    "LINKS": {
        "kind": "list",
        "strategy": "append",
        "default": [],
        "current_first": True,
    },
    "PKGS": {
        "kind": "list",
        "strategy": "append_unique",
        "default": [],
        "current_first": True,
    },
    "ENV_LIST": {
        "kind": "list",
        "strategy": "append_unique",
        "default": [],
        "current_first": True,
    },
    "ENV": {
        "kind": "dict",
        "strategy": "env_overlay",
        "default": {},
        "current_wins": True,
    },
}


def _is_empty_text(value):
    return isinstance(value, str) and value.strip() == ""


def _resolve_subsystem_id(subsystem_id, fallback_id=None):
    if wrapped_test_undefined(subsystem_id) or subsystem_id is None or _is_empty_text(subsystem_id):
        subsystem_id = fallback_id

    if wrapped_test_undefined(subsystem_id) or subsystem_id is None or _is_empty_text(subsystem_id):
        raise AnsibleError("lookup('merge_subsys', ...) requires id or fallback_id")

    if not isinstance(subsystem_id, str):
        raise AnsibleError("lookup('merge_subsys', ...) id must be a string")

    return subsystem_id.strip()


def _artifact_defaults(contrib):
    if wrapped_test_undefined(contrib) or contrib is None or _is_empty_text(contrib):
        raise AnsibleError("lookup('merge_subsys', ...) requires contrib")

    artifact = str(contrib).strip()
    defaults = ARTIFACT_DEFAULTS.get(artifact)
    if defaults is None:
        raise AnsibleError("unknown merge_subsys contrib artifact '{}'".format(artifact))
    return artifact, defaults


def _resolve_bool_option(value, default):
    if wrapped_test_undefined(value) or value is None:
        return default
    return _truthy(value)


def merge_subsys_value(variables, subsystem_id, contrib, **kwargs):
    """Merge one subsystem contrib artifact with its current global artifact.

    Args:
        variables: Raw Ansible variable mapping.
        subsystem_id: Subsystem id to read from C(SUBSYSTEM).
        contrib: Artifact key under C(contrib), such as C(BINS) or C(ENV).
        **kwargs: Optional overrides matching the lookup plugin options.

    Returns:
        Merged artifact value.
    """
    variables = _raw_copy_template_data(variables or {})
    subsystem_id = _resolve_subsystem_id(subsystem_id, fallback_id=kwargs.get("fallback_id"))
    artifact, defaults = _artifact_defaults(contrib)

    path = kwargs.get("path")
    if wrapped_test_undefined(path) or path is None or _is_empty_text(path):
        path = "contrib.{}".format(artifact)

    current_name = kwargs.get("current")
    if wrapped_test_undefined(current_name) or current_name is None or _is_empty_text(current_name):
        current_name = artifact

    default = kwargs.get("default")
    if wrapped_test_undefined(default) or default is None:
        default = defaults["default"]

    strategy = kwargs.get("strategy")
    if wrapped_test_undefined(strategy) or strategy is None:
        strategy = defaults["strategy"]

    active = _resolve_bool_option(kwargs.get("active"), True)
    active_path = kwargs.get("active_path")
    if wrapped_test_undefined(active_path) or active_path is None or _is_empty_text(active_path):
        active_path = "active"

    current = _dict_get_raw(variables, current_name, defaults["default"])
    subsystems = _dict_get_raw(variables, "SUBSYSTEM", {})
    record = _dict_get_raw(subsystems, subsystem_id, {})

    incoming = default
    if (not active) or _truthy(get_path(record, active_path, default=False)):
        incoming = get_path(record, path, default=default)

    if defaults["kind"] == "list":
        current_first = _resolve_bool_option(
            kwargs.get("current_first"), defaults.get("current_first", True)
        )
        payloads = [current, incoming] if current_first else [incoming, current]
        result = merge_list(payloads, strategy=strategy)
    elif defaults["kind"] == "dict":
        current_wins = _resolve_bool_option(
            kwargs.get("current_wins"), defaults.get("current_wins", True)
        )
        payloads = [incoming, current] if current_wins else [current, incoming]
        result = merge_dict(payloads, strategy=strategy)
    else:
        raise AnsibleError("unsupported merge_subsys artifact kind '{}'".format(defaults["kind"]))

    get_expr = kwargs.get("get")
    if not (wrapped_test_undefined(get_expr) or get_expr is None):
        return get_path(result, get_expr)
    return result


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        variables = variables or {}
        if len(terms) > 0:
            raise AnsibleError(
                "lookup('merge_subsys', ...) does not support positional terms; use id=..."
            )

        result = merge_subsys_value(
            variables,
            kwargs.get("id"),
            kwargs.get("contrib"),
            fallback_id=kwargs.get("fallback_id"),
            path=kwargs.get("path"),
            current=kwargs.get("current"),
            strategy=kwargs.get("strategy"),
            default=kwargs.get("default"),
            active=kwargs.get("active"),
            active_path=kwargs.get("active_path"),
            current_wins=kwargs.get("current_wins"),
            current_first=kwargs.get("current_first"),
            get=kwargs.get("get"),
        )
        return [self._templar._engine.template(result)]
