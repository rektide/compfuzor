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


class FilterModule(object):
    def filters(self):
        return {"def": un_undefine}
