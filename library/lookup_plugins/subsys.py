from __future__ import annotations

DOCUMENTATION = """
    name: subsys
    author: compfuzor
    short_description: Resolve one subsystem envelope from SUBSYSTEM
    description:
      - Looks up one subsystem by id from C(SUBSYSTEM) and returns a normalized envelope.
      - Accepts exactly one positional term (the subsystem id).
      - Optional C(name=) provides an alias label in the returned envelope.
      - Optional C(get=) returns one path from the envelope using shared get-path semantics.
      - Optional C(default=) is used when C(get=) path resolution fails.
      - Optional C(bypass=) accepts a string or list of extra bypass variable names to check.
      - Optional C(domain=) enables domain-level bypass via C(<DOMAIN>_BYPASS).
    options:
      _terms:
        description:
          - Positional terms are not supported.
          - Use C(id=...) and optional C(fallback_id=...) instead.
        required: false
      id:
        description:
          - Optional keyword subsystem id to resolve.
          - Preferred over positional terms for explicit calls.
      name:
        description:
          - Optional alias/logical name for caller-facing labeling.
      fallback_id:
        description:
          - Optional fallback subsystem id used when the positional id is empty/undefined.
      get:
        description:
          - Optional dotted path to read from the computed envelope.
      default:
        description:
          - Optional fallback when C(get=) path is missing.
      bypass:
        description:
          - Optional string or list of extra bypass variable names to check in addition
            to the automatic C(<SUBSYSTEM>_BYPASS) variable.
      domain:
        description:
          - Optional domain label enabling C(<DOMAIN>_BYPASS) as an additional bypass source.
"""

EXAMPLES = """
- name: Resolve whole subsystem envelope
  ansible.builtin.set_fact:
    get_urls_subsys: "{{ lookup('subsys', id='get_urls') }}"

- name: Resolve one field from subsystem
  ansible.builtin.set_fact:
    get_urls_active: "{{ lookup('subsys', id='get_urls', get='active', default=false) }}"

- name: Resolve with alias name
  ansible.builtin.set_fact:
    download_subsys: "{{ lookup('subsys', id='get_urls', name='downloads') }}"

- name: Resolve using fallback subsystem id
  ansible.builtin.set_fact:
    active_downloads: "{{ lookup('subsys', id=subsystem_id, name=subsystem_name, fallback_id='get_urls', get='active') }}"
"""

RETURN = """
_value:
  description:
    - A normalized subsystem envelope or one extracted field when C(get=) is provided.
  type: raw
"""

import os
import sys

from ansible.errors import AnsibleError, AnsibleTypeError
from ansible.module_utils.datatag import native_type_name
from ansible.plugins.lookup import LookupBase
from ansible.plugins.test.core import wrapped_test_undefined


_FILTER_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "filter_plugins")
)
if _FILTER_DIR not in sys.path:
    sys.path.insert(0, _FILTER_DIR)

from get import get_path  # noqa: E402


def _to_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _resolve_bypass(variables, subsystem_id, domain=None, extra_bypass=None):
    bypass_vars = [subsystem_id.upper() + "_BYPASS"]
    if domain and isinstance(domain, str) and domain.strip():
        bypass_vars.append(domain.strip().upper().replace("-", "_") + "_BYPASS")
    if extra_bypass:
        if isinstance(extra_bypass, str):
            bypass_vars.append(extra_bypass)
        elif isinstance(extra_bypass, (list, tuple)):
            bypass_vars.extend(v for v in extra_bypass if isinstance(v, str))
    for var_name in bypass_vars:
        val = variables.get(var_name)
        if val is not None and not wrapped_test_undefined(val):
            if _to_bool(val):
                return True
    return False


def _compute_state(record):
    if not isinstance(record, dict):
        return "absent"

    state = record.get("state")
    if isinstance(state, str) and state.strip():
        return state.strip()

    requested = _to_bool(record.get("requested", False))
    bypassed = _to_bool(record.get("bypassed", False))
    valid = _to_bool(record.get("valid", True))

    if requested and (not bypassed) and valid:
        return "active"
    if requested and bypassed:
        return "bypassed"
    if requested and (not valid):
        return "invalid"
    if requested:
        return "requested"
    return "absent"


def _build_envelope(subsystems, subsystem_id, name=None, variables=None, domain=None, extra_bypass=None):
    subsystems_map = subsystems if isinstance(subsystems, dict) else {}
    record = subsystems_map.get(subsystem_id)
    record = record if isinstance(record, dict) else {}
    found = bool(record)

    state = _compute_state(record)
    active = _to_bool(record.get("active", state == "active"))
    requested = _to_bool(record.get("requested", found and state != "absent"))
    bypassed = _to_bool(record.get("bypassed", state == "bypassed"))

    if variables is not None:
        var_bypassed = _resolve_bypass(variables, subsystem_id, domain=domain, extra_bypass=extra_bypass)
        bypassed = bypassed or var_bypassed
        active = requested and (not bypassed)
        state = "bypassed" if (requested and bypassed) else ("active" if active else state)

    valid = _to_bool(record.get("valid", state not in {"invalid", "absent"}))
    reasons = record.get("reasons", [])
    if reasons is None:
        reasons = []

    spec = record.get("spec")
    if spec is None:
        spec = []
    contrib = record.get("contrib")
    if not isinstance(contrib, dict):
        contrib = {}

    return {
        "id": subsystem_id,
        "name": name if isinstance(name, str) and name.strip() else subsystem_id,
        "found": found,
        "record": record,
        "state": state,
        "active": active,
        "requested": requested,
        "bypassed": bypassed,
        "valid": valid,
        "reasons": reasons,
        "spec": spec,
        "contrib": contrib,
    }


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        variables = variables or {}

        if len(terms) > 0:
            raise AnsibleError(
                "lookup('subsys', ...) does not support positional ids; use id=..."
            )

        keyword_id = kwargs.get("id")
        subsystem_id = keyword_id
        fallback_id = kwargs.get("fallback_id")

        if wrapped_test_undefined(subsystem_id) or subsystem_id is None:
            subsystem_id = fallback_id

        if isinstance(subsystem_id, str) and subsystem_id.strip() == "":
            subsystem_id = fallback_id

        if not isinstance(subsystem_id, str):
            raise AnsibleTypeError(
                "subsystem id must be {} not {}".format(
                    native_type_name(str), native_type_name(subsystem_id)
                ),
                obj=subsystem_id,
            )

        subsystem_id = subsystem_id.strip()
        if not subsystem_id:
            raise AnsibleError(
                "lookup('subsys', ...) requires a non-empty subsystem id or fallback_id"
            )

        name = kwargs.get("name")
        get_expr = kwargs.get("get")
        default = kwargs.get("default")
        domain = kwargs.get("domain")
        extra_bypass = kwargs.get("bypass")

        envelope = _build_envelope(
            variables.get("SUBSYSTEM", {}),
            subsystem_id,
            name=name,
            variables=variables,
            domain=domain,
            extra_bypass=extra_bypass,
        )

        if get_expr is not None:
            resolved = get_path(envelope, get_expr, default=default)
            return [self._templar._engine.template(resolved)]

        return [self._templar._engine.template(envelope)]
