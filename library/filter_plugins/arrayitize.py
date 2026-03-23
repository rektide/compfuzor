import collections.abc
import numbers
from ansible.module_utils.six import string_types


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


def arrayitize(*a, **kw):
    """Place passed in arguments into an array"""

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
