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


@pass_context
def owner_group_fields(context, row, owner=None, group=None):
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
def subsystem_base_fields(
    context,
    subsystem,
    requested=None,
    bypassed=None,
    valid=None,
    errors=None,
    status=None,
):
    resolved_errors = (
        errors if errors is not None else _context_var(context, "errors", [])
    )
    if resolved_errors is None:
        resolved_errors = []

    resolved_requested = (
        requested
        if requested is not None
        else _context_var(
            context, "_subsystem_requested", _context_var(context, "requested", False)
        )
    )
    resolved_bypassed = (
        bypassed
        if bypassed is not None
        else _context_var(
            context, "_subsystem_bypassed", _context_var(context, "bypassed", False)
        )
    )
    resolved_valid = (
        valid
        if valid is not None
        else _context_var(context, "_subsystem_valid", len(resolved_errors) == 0)
    )

    requested_bool = _to_bool(resolved_requested)
    bypassed_bool = _to_bool(resolved_bypassed)
    valid_bool = _to_bool(resolved_valid)
    active_bool = requested_bool and (not bypassed_bool) and valid_bool

    resolved_status = (
        status if status is not None else _context_var(context, "_subsystem_status")
    )
    if resolved_status is None:
        if active_bool:
            resolved_status = "active"
        elif bypassed_bool:
            resolved_status = "bypassed"
        elif not valid_bool:
            resolved_status = "invalid"
        else:
            resolved_status = "requested"

    result = {
        "status": resolved_status,
        "requested": requested_bool,
        "bypassed": bypassed_bool,
        "valid": valid_bool,
        "active": active_bool,
        "reasons": resolved_errors,
    }

    if _has_value(subsystem):
        result["subsystem"] = subsystem

    return result


class FilterModule(object):
    def filters(self):
        return {
            "owner_group_fields": owner_group_fields,
            "subsystem_base_fields": subsystem_base_fields,
        }
