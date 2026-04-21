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


class FilterModule(object):
    def filters(self):
        return {
            "owner_group_fields": owner_group_fields,
        }
