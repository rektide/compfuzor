from __future__ import absolute_import, division, print_function

__metaclass__ = type

from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

from _subsystem_utils import _as_list, _dedupe_preserve


def _is_nothing(value):
    """True when value is Python None or Ansible's undefined sentinel."""
    if value is None:
        return True
    if wrapped_test_undefined(value):
        return True
    return False


@accept_args_markers
def concat2(left, right, unique=False):
    """Concatenate two values, tolerating undefined/None on either side.

    Both inputs are normalized to lists via _as_list.
    Ansible undefined sentinels and Python None are treated as empty lists.
    When unique=True, deduplicate the result preserving order.
    """
    left = [] if _is_nothing(left) else _as_list(left)
    right = [] if _is_nothing(right) else _as_list(right)
    combined = left + right
    if unique:
        return _dedupe_preserve(combined)
    return combined


class FilterModule(object):
    def filters(self):
        return {
            "concat2": concat2,
        }
