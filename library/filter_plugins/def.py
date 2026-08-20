from ansible.errors import AnsibleFilterError
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

from template_data import is_omit



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

    ``skip_omit`` (default ``True``) treats the omit sentinel like an
    undefined value wherever it appears mid-chain -- the sentinel leaking
    out of a nested lookup/default is the SYSTEMD_SCOPE shadow bug class,
    and skipping it is what "omit" means almost everywhere. The sentinel is
    truthy, so it flows through ``default()``, ``default(x, true)`` and
    ``falsy=True`` alike; only skip_omit catches it at the source, before
    it renders as garbage. One deliberate exception: ``omit`` as the FINAL
    argument of a multi-argument chain passes through, preserving the
    conditionally-present module-param idiom (``owner|def(OWNER, omit)``) —
    a fallback terminator is definitionally last, so a sentinel anywhere
    earlier is a leak by construction, while ``def(X, omit)`` stays the way
    to say "strip the param when nothing matched". ``skip_omit=False``
    restores full pass-through everywhere (the old default), for the rare
    caller that wants to treat a real sentinel as an ordinary value.

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
    skip_omit = kwargs.get("skip_omit", True)
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

    # The module-param terminator: omit as the FINAL argument of a
    # multi-argument chain is deliberate ("strip the param when nothing
    # matched"), so it is returned unvalidated rather than skipped; a
    # sentinel anywhere earlier is a leak and is skipped (skip_omit).
    terminator = a and len(a) > 1 and is_omit(a[-1])
    walk = a[:-1] if (skip_omit and terminator) else a

    if skip_omit:
        _plain_skip = should_skip

        def should_skip(v):  # noqa: F811 — deliberate layered closure
            return is_omit(v) or _plain_skip(v)

    for candidate in walk:
        if not should_skip(candidate):
            if enum is not None and candidate not in enum:
                raise AnsibleFilterError(
                    "def: value {0!r} is not one of enum {1!r}".format(candidate, list(enum))
                )
            return candidate
    if terminator:
        return a[-1]
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
