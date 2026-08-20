from ansible.errors import AnsibleFilterError
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

# The omit sentinel: a truthy singleton class object, so neither plain
# default() nor the boolean default() form (nor falsy=True here) skips it --
# it flows through and later renders as '' (or strips the module param).
# ansible-core 2.21 exposes it as ansible._internal._templating._utils.Omit;
# there is no stable public import, so degrade to a never-matching
# placeholder on older cores rather than crash.
try:
    from ansible._internal._templating._utils import Omit as _OMIT
except ImportError:  # pragma: no cover - ansible-core version dependent
    _OMIT = None


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

    ``skip_omit=True`` additionally skips the omit sentinel wherever it
    appears in the chain, composable with every ``falsy`` mode. Off by
    default because ``def(X, omit)`` is the established idiom for
    conditionally-present module params (``owner|def(OWNER, omit)``).
    The sentinel is truthy, so omit flows through ``default()``,
    ``default(x, true)`` and ``falsy=True`` alike; only skip_omit catches
    it at the source, before it renders as ''.

    ``enum=['a', 'b']`` validates the chosen (non-skipped) value and raises
    AnsibleFilterError when it is not a member. For enum-like selection
    vars (scopes, modes) this converts a silent ''-leak or typo into a loud
    render-time failure instead of a silent equality-miss against every
    branch. A None result (everything skipped) is returned unvalidated.

    Backward compatibility (``falsy=False``, the default):

    - ``def(X)`` (1 arg): unchanged. X defined -> X; X undefined -> None.
    - ``def(X, Y)`` (2 args): X defined -> X; X undefined & Y defined -> Y;
      both undefined -> None. (The old implementation returned Y's undefined
      marker in the both-undefined case; this is a strict improvement.)
    - ``def(X, Y, Z, ...)`` (3+ args): new capability.
    """
    falsy = kwargs.get("falsy", False)
    skip_omit = kwargs.get("skip_omit", False)
    enum = kwargs.get("enum")

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

    if skip_omit and _OMIT is not None:
        _plain_skip = should_skip

        def should_skip(v):  # noqa: F811 — deliberate layered closure
            return v is _OMIT or _plain_skip(v)

    for candidate in a:
        if not should_skip(candidate):
            if enum is not None and candidate not in enum:
                raise AnsibleFilterError(
                    "def: value {0!r} is not one of enum {1!r}".format(candidate, list(enum))
                )
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
