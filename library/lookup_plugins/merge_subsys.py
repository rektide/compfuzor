from __future__ import annotations

DOCUMENTATION = """
    name: merge_subsys
    author: compfuzor
    short_description: Merge one subsystem contrib artifact into its global artifact
    description:
      - Reads C(SUBSYSTEM.<id>.contrib.<contrib>) and the matching current global artifact.
      - Dispatches to named value presets in C(library/filter_plugins/cfmerge.py).
      - Reads variables through raw-copy helpers so tagged template strings are not rendered during merge.
      - C(<SUBSYSTEM>_<CONTRIB>_BYPASS) suppresses only the selected incoming artifact.
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
          - Artifact key under C(contrib), such as C(BINS), C(ENV), C(ETC_FILES), C(PKGS), C(ENV_LIST), C(LINKS), or C(TOOL_VERSIONS).
      path:
        description:
          - Optional dotted path override for the incoming subsystem payload.
          - Defaults to C(contrib.<contrib>).
      current:
        description:
          - Optional current/global variable name.
          - Defaults to the C(contrib) value.
      preset:
        description:
          - Optional value preset override.
      default:
        description:
          - Optional missing incoming payload default.
      active:
        description:
          - When truthy, merge only when the subsystem active path is truthy.
      active_path:
        description:
          - Dotted path used for active gating. Defaults to C(active).
      order:
        description:
          - C(current-first) or C(incoming-first). Controls layer order before
            the artifact's preset runs.
      get:
        description:
           - Optional dotted path to extract from the merged result.
      domain:
        description:
          - Optional broad disarm scope for incoming BINS records.
          - Precedence is this option, the subsystem record C(domain), then C(id).
"""

EXAMPLES = """
- name: Merge python BINS
  ansible.builtin.set_fact:
    BINS: "{{ lookup('merge_subsys', id='python', contrib='BINS') }}"

- name: Merge sysctl package contributions
  ansible.builtin.set_fact:
    PKGS: "{{ lookup('merge_subsys', id='kernel_sysctl', contrib='PKGS') }}"

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
from template_data import dict_get_raw as _dict_get_raw, raw_copy_template_data as _raw_copy_template_data, truthy as _truthy  # noqa: E402
from cfmerge import run_value_preset, value_preset_metadata  # noqa: E402
from bin_disarm import annotate_bins  # noqa: E402

_LOOKUP_DIR = os.path.abspath(os.path.dirname(__file__))
if _LOOKUP_DIR not in sys.path:
    sys.path.insert(0, _LOOKUP_DIR)

from subsys import (  # noqa: E402
    _compute_state,
    _is_tagged_template,
    _template_value,
)


ARTIFACT_DEFAULTS = {
    "BINS": {
        "preset": "bins_generated",
        "order": "current-first",
    },
    "ETC_FILES": {
        "preset": "append",
        "order": "current-first",
    },
    "LINKS": {
        "preset": "append",
        "order": "current-first",
    },
    "PKGS": {
        "preset": "append_unique",
        "order": "current-first",
    },
    "ENV_LIST": {
        "preset": "append_unique",
        "order": "current-first",
    },
    "ETC_DIRS": {
        "preset": "append",
        "order": "current-first",
    },
    "ENV": {
        "preset": "overlay",
        "order": "incoming-first",
    },
    "ENV_PRIO": {
        "preset": "overlay",
        "order": "incoming-first",
    },
    "TOOL_VERSIONS": {
        "preset": "tool_versions_overlay",
        "order": "incoming-first",
    },
}

_VALID_ORDERS = {"current-first", "incoming-first"}


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


def _resolve_order(value, default):
    if wrapped_test_undefined(value) or value is None:
        return default
    if not isinstance(value, str) or value not in _VALID_ORDERS:
        raise AnsibleError(
            "merge_subsys order must be one of: {}".format(
                ", ".join(sorted(_VALID_ORDERS))
            )
        )
    return value


def _resolve_domain(explicit_domain, record, subsystem_id):
    if not (
        wrapped_test_undefined(explicit_domain)
        or explicit_domain is None
        or _is_empty_text(explicit_domain)
    ):
        return explicit_domain
    record_domain = get_path(record, "domain", default=None)
    if not (
        wrapped_test_undefined(record_domain)
        or record_domain is None
        or _is_empty_text(record_domain)
    ):
        return record_domain
    return subsystem_id


def merge_subsys_value(variables, subsystem_id, contrib, templar=None, **kwargs):
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

    preset = kwargs.get("preset")
    if wrapped_test_undefined(preset) or preset is None:
        preset = defaults["preset"]
    metadata = value_preset_metadata(preset)

    default = kwargs.get("default")
    if wrapped_test_undefined(default) or default is None:
        default = metadata["identity"]

    order = _resolve_order(kwargs.get("order"), defaults["order"])

    active = _resolve_bool_option(kwargs.get("active"), True)
    explicit_active_path = kwargs.get("active_path")
    has_active_path = not (wrapped_test_undefined(explicit_active_path) or explicit_active_path is None or _is_empty_text(explicit_active_path))

    current = _dict_get_raw(variables, current_name, metadata["identity"])
    subsystems = _dict_get_raw(variables, "SUBSYSTEM", {})
    record = _dict_get_raw(subsystems, subsystem_id, {})
    domain = _resolve_domain(kwargs.get("domain"), record, subsystem_id)
    artifact_bypass_name = "{}_{}_BYPASS".format(
        subsystem_id.upper().replace("-", "_"), artifact.upper().replace("-", "_")
    )
    artifact_bypassed = _truthy(
        _dict_get_raw(variables, artifact_bypass_name, False)
    )

    incoming = default
    if has_active_path:
        is_active = _truthy(get_path(record, explicit_active_path, default=False))
    else:
        is_active = _compute_state(
            record,
            variables,
            subsystem_id,
            domain=domain,
            templar=templar,
        )["active"]
    if ((not active) or is_active) and not artifact_bypassed:
        incoming = get_path(record, path, default=default)
        if _is_tagged_template(incoming):
            incoming = _template_value(incoming, templar)
        if artifact == "BINS":
            incoming = annotate_bins(
                incoming,
                origin_subsystem=subsystem_id,
                bypass_scope=domain,
            )

    get_expr = kwargs.get("get")
    if wrapped_test_undefined(get_expr):
        get_expr = None
    payloads = [current, incoming] if order == "current-first" else [incoming, current]
    return run_value_preset(payloads, preset=preset, get=get_expr)


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
            templar=self._templar,
            fallback_id=kwargs.get("fallback_id"),
            path=kwargs.get("path"),
            current=kwargs.get("current"),
            preset=kwargs.get("preset"),
            default=kwargs.get("default"),
            active=kwargs.get("active"),
            active_path=kwargs.get("active_path"),
            order=kwargs.get("order"),
            get=kwargs.get("get"),
            domain=kwargs.get("domain"),
        )
        return [self._templar._engine.template(result)]
