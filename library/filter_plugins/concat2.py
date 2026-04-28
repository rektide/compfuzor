from __future__ import absolute_import, division, print_function

__metaclass__ = type

from _subsystem_utils import _as_list, _dedupe_preserve


def concat2(left, right, unique=False):
    """Concatenate two values, tolerating undefined/None on either side.

    Both inputs are normalized to lists via _as_list.
    When unique=True, deduplicate the result preserving order.
    """
    combined = _as_list(left) + _as_list(right)
    if unique:
        return _dedupe_preserve(combined)
    return combined


class FilterModule(object):
    def filters(self):
        return {
            "concat2": concat2,
        }
