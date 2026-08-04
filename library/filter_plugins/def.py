from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


@accept_args_markers
def un_undefine(*a, **kwargs):
    """First argument passing the skip filter, else None.

    Walks ``a`` left-to-right and returns the first value that is not
    skipped; returns None if every argument is skipped or no arguments were
    given. A literal final fallback (``def(X, Y, 'default')``) works because
    literals are always defined.

    ``falsy`` keyword controls what counts as "skipped":

    - ``falsy=False`` (default) — skip only Ansible-undefined markers.
      Matches ``X|default(Y)``.
    - ``falsy=True`` — skip undefined AND Python-falsy values (None, ``''``,
      ``0``, ``False``, ``[]``, ``{}``). Matches ``X|default(Y, true)``.
    - ``falsy=[None, '']`` — skip undefined AND any value equal to an entry
      in the list. For when you want empty-string-skip but need to keep
      ``0`` or ``False``.

    Backward compatibility (``falsy=False``, the default):

    - ``def(X)`` (1 arg): unchanged. X defined -> X; X undefined -> None.
    - ``def(X, Y)`` (2 args): X defined -> X; X undefined & Y defined -> Y;
      both undefined -> None. (The old implementation returned Y's undefined
      marker in the both-undefined case; this is a strict improvement.)
    - ``def(X, Y, Z, ...)`` (3+ args): new capability.
    """
    falsy = kwargs.get("falsy", False)

    if falsy is True:
        def should_skip(v):
            return wrapped_test_undefined(v) or not v
    elif falsy:
        falsy_list = list(falsy)
        def should_skip(v):
            if wrapped_test_undefined(v):
                return True
            return any(v == f for f in falsy_list)
    else:
        def should_skip(v):
            return wrapped_test_undefined(v)

    for candidate in a:
        if not should_skip(candidate):
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
