from __future__ import annotations

from ansible._internal._templating._jinja_common import Marker
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


def unwrap(value):
    """unwrap"""
    if wrapped_test_undefined(value):
        return None
    # see `havingattr.py` for many questions surrounding this
    if isinstance(value, Marker) and value.data:
        value = value.data
    return value


@accept_args_markers
def defined_and_truthy(value) -> bool:
    """is-truthy that considers undefined to be falsy"""
    return not not unwrap(value)


@accept_args_markers
def falsy_or_undefined(value) -> bool:
    """is-falsy that considers undefined to be falsy"""
    return not unwrap(value)


class TestModule(object):
    def tests(self):
        return {"deftruthy": defined_and_truthy, "deffalsy": falsy_or_undefined}
