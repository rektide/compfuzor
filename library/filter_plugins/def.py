from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


@accept_args_markers
def un_undefine(*a):
    """Replace undefined with none"""
    if wrapped_test_undefined(a[0]):
        if len(a) > 1:
            return a[1]
        return None
    return a[0]


@accept_args_markers
def truthy(*a):
    """Replace undefined with none"""
    if wrapped_test_undefined(a[0]):
        if len(a) > 1:
            return not not a[1]
        return False
    return not not a[0]


@accept_args_markers
def lengthy(*a):
    """True if value is list-like with length > 0"""
    value = a[0]
    if wrapped_test_undefined(value):
        if len(a) > 1:
            value = a[1]
        else:
            return False
    try:
        return len(value) > 0
    except TypeError:
        return False


class FilterModule(object):
    def filters(self):
        return {"def": un_undefine, "truthy": truthy, "deflengthy": lengthy}
