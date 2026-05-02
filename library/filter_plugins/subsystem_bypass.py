from __future__ import absolute_import, division, print_function

__metaclass__ = type

import os
import sys

from jinja2 import pass_context

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from _subsystem_utils import _context_var, _has_value


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


class FilterModule(object):
    def filters(self):
        return {
            "owner_group_fields": owner_group_fields,
        }
