"""DEPRECATED: Legacy mergeKeyed filter — unused, to be removed.

No live callers remain. The ``merge_list`` filter in ``cfmerge.py`` with a
configured ``merge_keyed`` preset is the replacement.

This module imports from ``merge_strategy.py`` which imports from ``merge.py``.
All three can be deleted together once confirmed dead.
"""
import os
import sys

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from merge_strategy import merge_with_strategy


def mergeKeyed(list1, list2, key="key", concat_fields=None):
    """Compatibility shim implemented via merge_with_strategy."""
    merged = merge_with_strategy(
        [{"items": list1}, {"items": list2}],
        {
            "items": {
                "op": "merge_keyed",
                "key": key,
                "concat_fields": concat_fields,
            }
        },
        include_aggregate=False,
    )
    return merged.get("items", [])


class FilterModule(object):
    def filters(self):
        return {"mergeKeyed": mergeKeyed}
