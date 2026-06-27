from ansible.plugins.test.core import wrapped_test_undefined


def combine2(*dicts):
    """Combine dicts, skipping None/undefined/empty/non-dict values.

    Unlike Ansible's built-in combine, callers can pass None or
    conditional expressions that evaluate to None for entries that
    should be omitted, without polluting the result with empty dicts
    or needing per-key null checks.
    """
    result = {}
    for d in dicts:
        if d is None:
            continue
        if wrapped_test_undefined(d):
            continue
        if not isinstance(d, dict):
            continue
        if not d:
            continue
        result.update(d)
    return result


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"combine2": combine2}
