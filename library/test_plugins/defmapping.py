from __future__ import annotations

from ansible._internal._templating._jinja_common import Marker
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


UNSET = object()


def unwrap(value):
    """unwrap"""
    if wrapped_test_undefined(value):
        return None
    if isinstance(value, Marker) and value.data:
        value = value.data
    return value


def resolve_value(value, default=UNSET, use_default_on_falsy=False):
    """Resolve marker/undefined values and optionally apply default fallback."""
    is_undefined = wrapped_test_undefined(value)
    value = unwrap(value)

    if is_undefined:
        if default is UNSET:
            return None
        return default

    if use_default_on_falsy and default is not UNSET and not value:
        return default

    return value


@accept_args_markers
def defined_and_mapping(value, default=UNSET, use_default_on_falsy=False) -> bool:
    """Mapping test: true if value is a dict-like mapping."""
    value = resolve_value(value, default, use_default_on_falsy)
    return isinstance(value, dict)


class TestModule(object):
    def tests(self):
        return {"defmapping": defined_and_mapping}
