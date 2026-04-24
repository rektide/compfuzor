from __future__ import absolute_import, division, print_function

__metaclass__ = type

from jinja2 import pass_context

from _subsystem_utils import (
    _context_var,
    _to_bool,
    _has_value,
    _normalize_bypass_var_name,
    _dedupe,
)


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

    if bypass_vars is None:
        return defaults

    if isinstance(bypass_vars, bool):
        return defaults if bypass_vars else []

    if isinstance(bypass_vars, str):
        if bypass_vars.strip().lower() == "true":
            return defaults
        explicit_name = _normalize_bypass_var_name(bypass_vars)
        return [explicit_name] if explicit_name else []

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
