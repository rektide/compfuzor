"""DEPRECATED: Legacy list-coercion filter — all callers migrated.

Every ``arrayitize`` call site has been migrated to ``normalize(to='list')``
(iteration) or ``join2`` (text-rendering joins). The filter is still
registered for soak time but has no live callers.

``normalize(to='list')`` is the replacement for most cases. It coerces
``None``, undefined, and ``False`` to ``[]``, wraps scalars/strings/mappings
as single items, and copies sequences — but keeps ``True`` as ``[True]``
(unlike arrayitize, which dropped it). ``join2`` covers the
``arrayitize | join`` pattern and drops booleans for text rendering.

This module can be deleted once the migration has soaked.
"""
import collections.abc
import numbers

from ansible.module_utils.six import string_types
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


def isList(value):
    return isinstance(value, collections.abc.Sequence) and not isinstance(
        value, string_types
    )


def _normalize_single(value):
    if value is None or value is True or value is False:
        return []
    if isinstance(value, string_types):
        return [value]
    if isinstance(value, numbers.Number):
        return [value]
    if isList(value):
        return list(value)
    return [value]


@accept_args_markers
def arrayitize(*a, **kw):
    """Place passed in arguments into an array"""

    if len(a) == 1 and wrapped_test_undefined(a[0]):
        return []

    if len(a) == 1:
        return _normalize_single(a[0])

    val = []
    for el in a:
        if el is None:
            continue
        if isList(el):
            val.extend(el)
        else:
            val.append(el)
    return val


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"arrayitize": arrayitize}
