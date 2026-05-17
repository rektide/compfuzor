from __future__ import annotations

DOCUMENTATION = """
    name: subsys
    author: compfuzor
    short_description: Resolve one subsystem from SUBSYSTEM
    description:
      - Looks up one subsystem by id from C(SUBSYSTEM) and returns the requested
        value or a minimal envelope.
      - Optional C(get=) extracts one path from the subsystem record. State paths
        (active, bypassed, requested, valid) are computed from the record and
        variables. Data paths (contrib, spec, or any dotted path) are extracted
        from the record with tagged template leaf strings resolved through the
        templar so no TrustedAsTemplate tags survive into the output.
      - Without C(get=), returns a minimal envelope with computed state and
        leaf-resolved data fields.
    options:
      id:
        description: Subsystem id to resolve.
        required: true
      name:
        description: Alias label included in envelope output.
      fallback_id:
        description: Subsystem id used when id is absent or empty.
      get:
        description: Dotted path to extract. State paths (active, bypassed,
          requested, valid) are computed. All other paths extract from the
          record with tagged leaf strings resolved.
      default:
        description: Fallback when get path resolution fails.
      bypass:
        description: Extra bypass variable names (string or list).
      domain:
        description: Domain label enabling DOMAIN_BYPASS as bypass source.
"""

EXAMPLES = """
- name: Gate on subsystem active state
  debug:
    msg: kernel_modprobe is active
  when: lookup('subsys', id='kernel_modprobe', domain='kernel', get='active', default=false) | bool

- name: Extract subsystem contrib
  set_fact:
    contrib: "{{ lookup('subsys', id='kernel_modprobe', domain='kernel', get='contrib', default={}) }}"

- name: Get full envelope
  set_fact:
    envelope: "{{ lookup('subsys', id='kernel_modprobe', domain='kernel') }}"
"""

RETURN = """
_value:
  description: Requested path value or minimal envelope.
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
from merge import _raw_copy_template_data, _dict_get_raw, _is_nothing, _truthy  # noqa: E402


_STATE_PATHS = frozenset({"active", "bypassed", "requested", "valid"})


def _is_tagged_template(value):
    try:
        from ansible.module_utils._internal._datatag import _AnsibleTaggedStr
        return isinstance(value, _AnsibleTaggedStr)
    except ImportError:
        return False


def _resolve_leaf_strings(value, templar):
    """Walk a data tree and resolve tagged template leaf strings.

    Container structure (dicts, lists) is preserved as-is. Only leaf strings
    carrying the TrustedAsTemplate tag are resolved through the templar.
    Non-tagged strings and non-string values pass through unchanged.

    This does NOT modify the underlying SUBSYSTEM fact — it operates on the
    already raw-copied output.
    """
    if isinstance(value, dict):
        return {k: _resolve_leaf_strings(v, templar) for k, v in value.items()}
    if isinstance(value, list):
        return [_resolve_leaf_strings(item, templar) for item in value]
    if isinstance(value, str) and _is_tagged_template(value):
        return _template_value(value, templar)
    return value


def _resolve_record(variables, subsystem_id):
    subsystems = _raw_copy_template_data(variables.get("SUBSYSTEM", {}))
    record = _dict_get_raw(subsystems, subsystem_id, {})
    if isinstance(record, dict) and record:
        return _raw_copy_template_data(record)
    return {}


def _template_value(value, templar=None):
    if templar is None or not isinstance(value, str):
        return value
    try:
        return templar.template(value)
    except Exception:
        return value


def _resolve_requested_from_vars(variables, subsystem_id):
    var_name = subsystem_id.upper().replace("-", "_")
    val = variables.get(var_name)
    if val is None or wrapped_test_undefined(val):
        return False
    return _truthy(val)


def _compute_requested(record, variables, subsystem_id, templar):
    explicit = record.get("requested")
    if explicit is not None:
        return _truthy(_template_value(explicit, templar))
    if variables is not None:
        return _resolve_requested_from_vars(variables, subsystem_id)
    return bool(record)


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
            if _truthy(val):
                return True
    return False


def _compute_bypassed(record, variables, subsystem_id, domain=None, extra_bypass=None, templar=None):
    explicit = record.get("bypassed")
    bypassed = _truthy(_template_value(explicit, templar)) if explicit is not None else False
    if variables is not None:
        bypassed = bypassed or _resolve_bypass(variables, subsystem_id, domain=domain, extra_bypass=extra_bypass)
    return bypassed


def _compute_valid(record, templar):
    return _truthy(_template_value(record.get("valid", True), templar))


def _classify_status(requested, bypassed, valid):
    if requested and not bypassed and valid:
        return "active"
    if requested and bypassed:
        return "bypassed"
    if requested and not valid:
        return "invalid"
    if requested:
        return "requested"
    return "absent"


def _compute_state(record, variables, subsystem_id, domain=None, extra_bypass=None, templar=None):
    requested = _compute_requested(record, variables, subsystem_id, templar)
    bypassed = _compute_bypassed(record, variables, subsystem_id, domain, extra_bypass, templar)
    valid = _compute_valid(record, templar)
    active = requested and not bypassed and valid
    return {
        "active": active,
        "requested": requested,
        "bypassed": bypassed,
        "valid": valid,
        "status": _classify_status(requested, bypassed, valid),
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

        record = _resolve_record(variables, subsystem_id)

        if get_expr is not None:
            get_expr = str(get_expr)

            if get_expr in ("active", "bypassed", "requested", "valid"):
                return [_compute_state(record, variables, subsystem_id, domain, extra_bypass, self._templar)[get_expr]]

            resolved = get_path(record, get_expr, default=default)
            return [_resolve_leaf_strings(resolved, self._templar)]

        st = _compute_state(record, variables, subsystem_id, domain, extra_bypass, self._templar)

        return [{
            "id": subsystem_id,
            "name": name if isinstance(name, str) and name.strip() else subsystem_id,
            "record": record,
            **st,
            "spec": _resolve_leaf_strings(record.get("spec", []), self._templar),
            "contrib": _resolve_leaf_strings(record.get("contrib", {}), self._templar),
        }]
