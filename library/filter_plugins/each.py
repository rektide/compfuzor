"""Record-list transformation filters for compfuzor Jinja templates.

``tag_each`` overlays fields onto every mapping record in a list, replacing
the ``map('combine', {...}) | list`` pattern.
"""

from __future__ import absolute_import, division, print_function

import collections.abc
import os
import sys

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from template_data import raw_copy_template_data, is_nothing  # noqa: E402


@accept_args_markers
def tag_each(records, tag=None, **fields):
    """Overlay fields onto every mapping record in a list.

    Non-mapping items are preserved unchanged. Undefined/None records
    return an empty list. Undefined field values are skipped.

        {{ contrib.BINS | tag_each(subsystem='kernel') }}
        {{ items | tag_each(tag={'subsystem': 'kernel', 'scope': 'user'}) }}

    Args:
        records: List of records, or a single mapping (wrapped to one item).
        tag: Optional mapping of fields, for names that collide with Python
            identifiers.
        **fields: Fields to overlay on each mapping record.

    Returns:
        A new list with overlaid records.
    """
    records = raw_copy_template_data(records)
    if is_nothing(records):
        return []
    if isinstance(records, collections.abc.Mapping):
        records = [records]
    elif not isinstance(records, list):
        raise AnsibleFilterError(
            "tag_each expects a list of records; got {}".format(type(records).__name__)
        )
    fields = raw_copy_template_data(fields)
    if tag is not None:
        tag = raw_copy_template_data(tag)
        if isinstance(tag, collections.abc.Mapping):
            fields = {**tag, **fields}
    fields = {k: v for k, v in fields.items() if not is_nothing(v)}
    return [
        dict(record, **fields) if isinstance(record, collections.abc.Mapping) else record
        for record in records
    ]


class FilterModule(object):
    def filters(self):
        return {
            "tag_each": tag_each,
        }
