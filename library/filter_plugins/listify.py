import collections
import numbers


def listify(*a, **kw):
    if not a[0]:
        return []
    if isinstance(a[0], list):
        return a[0]
    if isinstance(a[0], dict):
        return [{"key": k, "value": a[0][k]} for k in a[0]]
    if isinstance(a[0], tuple):
        return list(a[0])
    return [a[0]]


def concat(*a, **kw):
    res = []
    for item in a:
        res = res + listify(item)
    return res


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"listify": listify, "concat": concat}
