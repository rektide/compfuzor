from __future__ import absolute_import, division, print_function

__metaclass__ = type

from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


def _is_undefined(value):
    return wrapped_test_undefined(value)


@accept_args_markers
def get(value, path, default=None):
    """Safely traverse a dotted path through dict/list values.

    Returns `default` when any path segment is missing, types mismatch,
    or an Ansible undefined marker is encountered.
    """
    if _is_undefined(value):
        return default

    if path is None:
        return value

    path_text = str(path).strip()
    if path_text == "":
        return value

    current = value
    for segment in path_text.split("."):
        if _is_undefined(current) or current is None:
            return default

        if isinstance(current, dict):
            if segment not in current:
                return default
            current = current[segment]
            continue

        if isinstance(current, list):
            try:
                idx = int(segment)
            except (TypeError, ValueError):
                return default

            if idx < 0 or idx >= len(current):
                return default

            current = current[idx]
            continue

        return default

    if _is_undefined(current):
        return default
    return current


class FilterModule(object):
    def filters(self):
        return {
            "get": get,
        }
