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
    options:
      _terms:
        description:
          - Exactly one subsystem id to resolve.
        required: true
      name:
        description:
          - Optional alias/logical name for caller-facing labeling.
      get:
        description:
          - Optional dotted path to read from the computed envelope.
      default:
        description:
          - Optional fallback when C(get=) path is missing.
"""

EXAMPLES = """
- name: Resolve whole subsystem envelope
  ansible.builtin.set_fact:
    get_urls_subsys: "{{ lookup('subsys', 'get_urls') }}"

- name: Resolve one field from subsystem
  ansible.builtin.set_fact:
    get_urls_active: "{{ lookup('subsys', 'get_urls', get='active', default=false) }}"

- name: Resolve with alias name
  ansible.builtin.set_fact:
    download_subsys: "{{ lookup('subsys', 'get_urls', name='downloads') }}"
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


def _compute_state(record):
    if not isinstance(record, dict):
        return "absent"

    state = record.get("state")
    if isinstance(state, str) and state.strip():
        return state.strip()

    # Backward compatibility while migrating from status->state.
    status = record.get("status")
    if isinstance(status, str) and status.strip():
        return status.strip()

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


def _build_envelope(subsystems, subsystem_id, name=None):
    subsystems_map = subsystems if isinstance(subsystems, dict) else {}
    record = subsystems_map.get(subsystem_id)
    record = record if isinstance(record, dict) else {}
    found = bool(record)

    state = _compute_state(record)
    active = _to_bool(record.get("active", state == "active"))
    requested = _to_bool(record.get("requested", found and state != "absent"))
    bypassed = _to_bool(record.get("bypassed", state == "bypassed"))
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

        if len(terms) != 1:
            raise AnsibleError(
                "lookup('subsys', ...) expects exactly one positional subsystem id"
            )

        subsystem_id = terms[0]
        if not isinstance(subsystem_id, str):
            raise AnsibleTypeError(
                "subsystem id must be {} not {}".format(
                    native_type_name(str), native_type_name(subsystem_id)
                ),
                obj=subsystem_id,
            )

        name = kwargs.get("name")
        get_expr = kwargs.get("get")
        default = kwargs.get("default")

        envelope = _build_envelope(variables.get("SUBSYSTEM", {}), subsystem_id, name=name)

        if get_expr is not None:
            resolved = get_path(envelope, get_expr, default=default)
            return [self._templar._engine.template(resolved)]

        return [self._templar._engine.template(envelope)]
