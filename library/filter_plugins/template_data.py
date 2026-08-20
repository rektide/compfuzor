"""Safe traversal of Ansible template data without rendering it.

Merge and lookup code use this boundary before inspecting container shape. It
unwraps Ansible lazy containers through their non-rendering hooks while keeping
data tags on template strings intact for later evaluation.

Additional raw data-access helpers (dict_get_raw, is_nothing, truthy) are
provided for modules that need to read Ansible values without triggering
template resolution.
"""

from __future__ import absolute_import, division, print_function

from ansible.plugins.test.core import wrapped_test_undefined

__all__ = ["raw_copy_template_data", "dict_get_raw", "is_nothing", "truthy", "is_omit"]

# The omit sentinel: a truthy singleton class object, so neither plain
# default() nor the boolean default() form (nor falsy=... filters) skips it --
# it flows through and later renders as '<<Omit>>' garbage once any filter
# stringifies it. ansible-core 2.21 exposes it as
# ansible._internal._templating._utils.Omit (the _templaring spelling that
# used to live in def.py was a typo the guarded import silently swallowed,
# so skip_omit never matched anything); there is no stable public import,
# so degrade to a never-matching check on older cores rather than crash.
try:
    from ansible._internal._templating._utils import Omit as _OMIT
except ImportError:  # pragma: no cover - ansible-core version dependent
    _OMIT = None


def is_omit(value):
    """True when value is Ansible's omit sentinel.

    Text-rendering filters (join2 and friends) drop it: they are terminal,
    so no downstream module-param stripping can consume the sentinel and
    stringifying it only produces garbage. Selection filters (``def`` with
    ``skip_omit=True``) use the same check at the source.
    """
    return _OMIT is not None and value is _OMIT


def raw_copy_template_data(value):
    """Copy lazy Ansible containers without evaluating template values.

    Args:
        value: Any Ansible/Jinja value. Lazy containers are copied through
            ``_non_lazy_copy()`` before ordinary traversal. Internal
            ``_LazyValue`` objects are unwrapped through ``value``.

    Returns:
        A plain container tree. Tagged strings retain their tags and are not
        rendered as part of the copy.
    """
    if value is None or wrapped_test_undefined(value):
        return value

    non_lazy_copy = getattr(value, "_non_lazy_copy", None)
    if callable(non_lazy_copy):
        return raw_copy_template_data(non_lazy_copy())

    try:
        from ansible._internal._templating._lazy_containers import _LazyValue

        if isinstance(value, _LazyValue):
            return raw_copy_template_data(value.value)
    except ImportError:
        pass

    if isinstance(value, dict):
        return {
            raw_copy_template_data(key): raw_copy_template_data(item)
            for key, item in dict.items(value)
        }
    if isinstance(value, list):
        return [raw_copy_template_data(item) for item in list.__iter__(value)]
    if isinstance(value, tuple):
        return tuple(raw_copy_template_data(item) for item in tuple.__iter__(value))
    return value


def dict_get_raw(mapping, key, default=None):
    """Read one dict key without calling lazy container accessors.

    Args:
        mapping: Candidate dictionary.
        key: Key to read.
        default: Value returned when ``mapping`` is not a dict or the key
            is absent.

    Returns:
        The raw dict value or ``default``.
    """
    if not isinstance(mapping, dict):
        return default
    try:
        return dict.__getitem__(mapping, key)
    except KeyError:
        return default


def is_nothing(value):
    """True when value is None or Ansible undefined."""
    return value is None or wrapped_test_undefined(value)


def truthy(value):
    """Convert Ansible values to bool (strings checked as non-empty)."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return bool(value.strip())
    return bool(value)


class FilterModule(object):
    """Make this internal support module valid for Ansible plugin discovery."""

    def filters(self):
        return {}
