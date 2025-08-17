from __future__ import annotations

from ansible._internal._templating._jinja_common import Marker
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


def unwrap(value):
    """Guard and unwrap, to only look for dictionary things"""
    if wrapped_test_undefined(value):
        return None
    if not value:
        return value
    # i can't remember if i'm just making this up?
    # not finding good source references so maybe?
    # i don't really know what else might be a marker or why: vault stuff maybe?
    # we're in a test so this is crazy hard to figure out:
    #   temporarily move to a filter for future exploration
    if isinstance(value, Marker) and value.data:
        value = value.data
    if not isinstance(value, dict):
        return False
    return value


@accept_args_markers
def having_attr(value, *attr_names: str) -> bool:
    """Whether `value` has all the `attr_names`"""
    value = unwrap(value)
    if not value:
        return False

    for attr_name in attr_names:
        if not value.get(attr_name):
            return False
    return True


@accept_args_markers
def having_any(value: object, *attr_names: str) -> bool:
    """Whether `value` has any of the `attr_names`"""
    value = unwrap(value)
    if not value:
        return False

    for attr_name in attr_names:
        if value.get(attr_name):
            return True
    return False


class TestModule(object):
    def tests(self):
        return {
            "having": having_attr,
            "havingattr": having_attr,
            "havingany": having_any,
        }
