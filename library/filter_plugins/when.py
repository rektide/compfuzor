"""Conditional inclusion filters for compfuzor Jinja templates.

``when`` returns a value if any condition is truthy (OR semantics).
``whenAnd`` returns a value if all conditions are truthy (AND semantics).
Both return ``else_value`` (default None) when the condition fails, making
them composable with merge pipeline filters that skip None layers.
"""

from __future__ import absolute_import, division, print_function

import os
import sys

from ansible.template import accept_args_markers

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from template_data import truthy  # noqa: E402


@accept_args_markers
def when(value, *conditions, else_value=None):
    """Return ``value`` if any condition is truthy, else ``else_value``.

    Ansible undefined conditions are treated as falsy, not raised.

        {{ 'status-dirs.sh' | when(STATUS_DIRS, STATUS_DIRS_SUDO) }}
        {{ 'privileged.sh' | when(ROOT, else_value='unprivileged.sh') }}
    """
    if any(truthy(c) for c in conditions):
        return value
    return else_value


@accept_args_markers
def whenAnd(value, *conditions, else_value=None):
    """Return ``value`` if all conditions are truthy, else ``else_value``.

    Ansible undefined conditions are treated as falsy, not raised.

        {{ 'system-bin.sh' | whenAnd(NOT_USERMODE, SYSTEMD_SCOPE == 'system') }}
    """
    if conditions and all(truthy(c) for c in conditions):
        return value
    return else_value


class FilterModule(object):
    def filters(self):
        return {
            "when": when,
            "whenAnd": whenAnd,
        }
