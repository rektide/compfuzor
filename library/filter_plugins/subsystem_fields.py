from __future__ import absolute_import, division, print_function

__metaclass__ = type

from jinja2 import pass_context


def _context_var(context, name, default=None):
    all_vars = context.get("vars", {})
    if isinstance(all_vars, dict) and name in all_vars:
        return all_vars[name]

    inventory_hostname = context.get("inventory_hostname")
    hostvars = context.get("hostvars", {})
    if isinstance(hostvars, dict):
        host_values = hostvars.get(inventory_hostname, {})
        if isinstance(host_values, dict) and name in host_values:
            return host_values[name]

    return default


def _to_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _has_value(value):
    return value is not None and value != ""


def _normalize_bypass_var_name(name):
    if name is None:
        return None
    text = str(name).strip()
    if not text:
        return None
    normalized = text.upper().replace("-", "_")
    if not normalized.endswith("_BYPASS"):
        normalized = normalized + "_BYPASS"
    return normalized


def _dedupe(values):
    seen = set()
    result = []
    for value in values:
        if value is None:
            continue
        if value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def _effective_bypass_vars(subsystem, bypass_vars=None, domain=None):
    """Resolve effective bypass variable names for a subsystem.

    Rules:
    - defaults: subsystem-level + optional domain-level bypass vars
    - bypass_vars omitted/None: use defaults
    - bypass_vars True: use defaults
    - bypass_vars False: disable defaults (no bypass vars)
    - bypass_vars "true": use defaults
    - bypass_vars "SOME_VAR": explicit replacement
    - bypass_vars ["SOME_VAR"]: explicit replacement
    - bypass_vars [True, "SOME_VAR"]: defaults + explicit supplement
    """
    defaults = _dedupe(
        [
            _normalize_bypass_var_name(subsystem),
            _normalize_bypass_var_name(domain),
        ]
    )

    # No override configured: use automatic defaults.
    if bypass_vars is None:
        return defaults

    # Boolean override:
    # - True: keep defaults
    # - False: disable bypass resolution for this subsystem.
    if isinstance(bypass_vars, bool):
        return defaults if bypass_vars else []

    # String override:
    # - "true": keep defaults
    # - any other string: explicit replacement with one var.
    if isinstance(bypass_vars, str):
        if bypass_vars.strip().lower() == "true":
            return defaults
        explicit_name = _normalize_bypass_var_name(bypass_vars)
        return [explicit_name] if explicit_name else []

    # Sequence override:
    # - include True (or "true") to include defaults
    # - string tokens add explicit vars
    # - without True, explicit list is full replacement
    if isinstance(bypass_vars, (list, tuple, set)):
        include_defaults = False
        explicit = []
        for item in bypass_vars:
            if isinstance(item, bool):
                include_defaults = include_defaults or item
                continue
            if item is None:
                continue
            token = str(item).strip()
            lowered = token.lower()
            if lowered == "":
                continue
            if lowered == "true":
                include_defaults = True
                continue
            if lowered == "false":
                continue
            explicit.append(_normalize_bypass_var_name(token))
        base = defaults if include_defaults else []
        return _dedupe(base + explicit)

    # Unknown override type: fall back to safe defaults.
    return defaults


@pass_context
def owner_group_fields(context, row, owner=None, group=None):
    """Resolve owner/group fields with row-first precedence.

    Precedence:
    1. row.owner / row.group
    2. explicit owner/group arguments
    3. context OWNER/GROUP vars
    Empty values are dropped from the result.
    """
    if not isinstance(row, dict):
        row = {}

    default_owner = _context_var(context, "OWNER")
    default_group = _context_var(context, "GROUP")

    resolved_owner = row.get("owner", owner if owner is not None else default_owner)
    resolved_group = row.get("group", group if group is not None else default_group)

    result = {}
    if _has_value(resolved_owner):
        result["owner"] = resolved_owner
    if _has_value(resolved_group):
        result["group"] = resolved_group
    return result


@pass_context
def subsystem_bypass_vars(context, subsystem, bypass_vars=None, domain=None):
    """Return effective bypass variable names for a subsystem."""
    return _effective_bypass_vars(subsystem, bypass_vars=bypass_vars, domain=domain)


@pass_context
def subsystem_bypassed(context, subsystem, bypass_vars=None, domain=None):
    """Return True if any effective bypass variable resolves truthy."""
    bypass_names = _effective_bypass_vars(
        subsystem, bypass_vars=bypass_vars, domain=domain
    )
    for name in bypass_names:
        if _to_bool(_context_var(context, name, False)):
            return True
    return False


class FilterModule(object):
    def filters(self):
        return {
            "owner_group_fields": owner_group_fields,
            "subsystem_bypass_vars": subsystem_bypass_vars,
            "subsystem_bypassed": subsystem_bypassed,
        }
