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


# Recognized get= paths that compute derived state rather than reading record data
_STATE_PATHS = frozenset({"active", "bypassed", "requested", "valid"})


def _is_tagged_template(value):
    """Check if value carries Ansible's TrustedAsTemplate tag."""
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


def _template_value(value, templar=None):
    """Resolve a single Jinja template string through the templar, pass-through on failure."""
    if templar is None or not isinstance(value, str):
        return value
    try:
        return templar.template(value)
    except Exception:
        return value


def _compute_state(record, variables, subsystem_id, domain=None, extra_bypass=None, templar=None):
    """Compute the full derived state for a subsystem record.

    Derives four booleans (active, requested, bypassed, valid) and a status
    label from the record and runtime variables. This is the single entry
    point for all subsystem state computation — both the subsys lookup and
    the merge_subsys lookup use it.

    requested resolution order:
      1. Explicit ``requested`` field on the record (template-resolved)
      2. Variable named after the subsystem uppercased (e.g. RUST for "rust")
      3. Non-empty record implies requested

    bypassed resolution order:
      1. Explicit ``bypassed`` field on the record (template-resolved)
      2. <SUBSYSTEM>_BYPASS variable (e.g. RUST_BYPASS)
      3. <DOMAIN>_BYPASS variable if domain is set (e.g. KERNEL_BYPASS)
      4. Extra bypass variable names passed via extra_bypass

    valid:
      Defaults to True; set ``valid`` on the record to override.

    active:
      requested AND NOT bypassed AND valid

    status:
      One of "active", "bypassed", "invalid", "requested", "absent".

    Returns a dict with keys: active, requested, bypassed, valid, status.
    """
    # --- requested ---
    explicit = record.get("requested")
    if explicit is not None:
        requested = _truthy(_template_value(explicit, templar))
    elif variables is not None:
        var_name = subsystem_id.upper().replace("-", "_")
        val = variables.get(var_name)
        requested = _truthy(val) if val is not None and not wrapped_test_undefined(val) else False
    else:
        requested = bool(record)

    # --- bypassed ---
    # Build the list of bypass variable names to check
    bypass_vars = [subsystem_id.upper() + "_BYPASS"]
    if domain and isinstance(domain, str) and domain.strip():
        bypass_vars.append(domain.strip().upper().replace("-", "_") + "_BYPASS")
    if extra_bypass:
        if isinstance(extra_bypass, str):
            bypass_vars.append(extra_bypass)
        elif isinstance(extra_bypass, (list, tuple)):
            bypass_vars.extend(v for v in extra_bypass if isinstance(v, str))
    bypassed = False
    explicit_bp = record.get("bypassed")
    if explicit_bp is not None:
        bypassed = _truthy(_template_value(explicit_bp, templar))
    if variables is not None:
        for bv in bypass_vars:
            val = variables.get(bv)
            if val is not None and not wrapped_test_undefined(val) and _truthy(val):
                bypassed = True
                break

    # --- valid ---
    valid = _truthy(_template_value(record.get("valid", True), templar))

    # --- active & status ---
    active = requested and not bypassed and valid
    if active:
        status = "active"
    elif requested and bypassed:
        status = "bypassed"
    elif requested and not valid:
        status = "invalid"
    elif requested:
        status = "requested"
    else:
        status = "absent"
    return {
        "active": active,
        "requested": requested,
        "bypassed": bypassed,
        "valid": valid,
        "status": status,
    }


class LookupModule(LookupBase):
    """Ansible lookup plugin ``subsys`` — resolve one subsystem from SUBSYSTEM."""

    def run(self, terms, variables=None, **kwargs):
        variables = variables or {}

        if len(terms) > 0:
            raise AnsibleError(
                "lookup('subsys', ...) does not support positional ids; use id=..."
            )

        # Resolve subsystem id, falling back to fallback_id if needed
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

        # Raw-copy the SUBSYSTEM dict and extract this subsystem's record,
        # avoiding triggering Ansible template resolution during read
        subsystems = _raw_copy_template_data(variables.get("SUBSYSTEM", {}))
        record = _dict_get_raw(subsystems, subsystem_id, {})
        if isinstance(record, dict) and record:
            record = _raw_copy_template_data(record)
        else:
            record = {}

        if get_expr is not None:
            get_expr = str(get_expr)

            # State paths: compute derived state and return the requested key
            if get_expr in ("active", "bypassed", "requested", "valid"):
                return [_compute_state(record, variables, subsystem_id, domain, extra_bypass, self._templar)[get_expr]]

            # Data paths: extract from record with tagged leaf strings resolved
            resolved = get_path(record, get_expr, default=default)
            return [_resolve_leaf_strings(resolved, self._templar)]

        # No get= — return the full envelope
        st = _compute_state(record, variables, subsystem_id, domain, extra_bypass, self._templar)

        return [{
            "id": subsystem_id,
            "name": name if isinstance(name, str) and name.strip() else subsystem_id,
            "record": record,
            **st,
            "spec": _resolve_leaf_strings(record.get("spec", []), self._templar),
            "contrib": _resolve_leaf_strings(record.get("contrib", {}), self._templar),
        }]
