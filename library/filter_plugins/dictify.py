from __future__ import annotations

import collections.abc

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import string_types
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


def _is_sequence(value):
    return isinstance(value, collections.abc.Sequence) and not isinstance(
        value, string_types
    )


@accept_args_markers
def dictify(value):
    """Normalize mappings and list-like shorthand into a mapping.

    Undefined and None normalize to an empty mapping. Existing mappings pass
    through. List entries may be strings, which become ``name: true``, or
    mappings, which overlay into the output. Scalar values are rejected so callers
    do not silently treat accidental strings as one-key maps.
    """
    if wrapped_test_undefined(value) or value is None:
        return {}

    if isinstance(value, collections.abc.Mapping):
        return dict(value)

    if not _is_sequence(value):
        raise AnsibleFilterError(
            "dictify expects a mapping or list-like value, got {}".format(
                type(value).__name__
            )
        )

    result = {}
    for item in value:
        if wrapped_test_undefined(item) or item is None:
            continue
        if isinstance(item, string_types):
            result[item] = True
            continue
        if isinstance(item, collections.abc.Mapping):
            result.update(dict(item))
            continue
        raise AnsibleFilterError(
            "dictify list entries must be strings or mappings, got {}".format(
                type(item).__name__
            )
        )
    return result


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"dictify": dictify}
