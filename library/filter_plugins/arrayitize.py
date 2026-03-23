import collections.abc
import numbers
from ansible.module_utils.six import string_types

listType = type(list())


def isList(value):
    return isinstance(value, collections.abc.Sequence) and not isinstance(
        value, string_types
    )


def arrayitize(*a, **kw):
    """Place passed in arguments into an array"""

    if len(a) == 1:
        value = a[0]

        if value is None:
            return []
        if value is True:
            return []
        if value is False:
            return []
        if isinstance(value, string_types):
            return [value]
        if isinstance(value, numbers.Number):
            return [value]
        if isList(value):
            return list(value)

    val = []
    for el in a:
        if el is None:
            continue
        if isList(el):
            val = val + list(el)
        else:
            val.append(el)
    return val


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"arrayitize": arrayitize}
