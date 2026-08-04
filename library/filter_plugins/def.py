from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


@accept_args_markers
def un_undefine(*a):
    """First non-undefined argument, else None.

    Generalizes the old binary ``def(X, Y)``. Walks ``a`` left-to-right and
    returns the first value that is not an Ansible-undefined marker; if every
    argument is undefined (or no arguments were given), returns None. A
    literal final fallback (``def(X, Y, 'default')``) works because literals
    are always defined.

    Backward compatibility:

    - ``def(X)`` (1 arg): unchanged. X defined -> X; X undefined -> None.
    - ``def(X, Y)`` (2 args): X defined -> X; X undefined & Y defined -> Y;
      both undefined -> None. (The old implementation returned Y's undefined
      marker in the both-undefined case; this is a strict improvement.)
    - ``def(X, Y, Z, ...)`` (3+ args): new capability.
    """
    for candidate in a:
        if not wrapped_test_undefined(candidate):
            return candidate
    return None


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
