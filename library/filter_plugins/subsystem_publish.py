"""Publish one subsystem record without templating unrelated records."""

from __future__ import annotations

import collections.abc

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


def _mapping(value, label: str) -> dict:
    if not isinstance(value, collections.abc.Mapping):
        raise AnsibleFilterError(
            "subsystem_publish: {} must be a mapping".format(label)
        )
    return dict(value)


@accept_args_markers
def publish_subsystem(subsystems, subsystem_id, record):
    """Insert one authoritative record through a raw-copy boundary."""
    subsystems = _mapping(raw_copy_template_data(subsystems), "SUBSYSTEM")
    record = _mapping(raw_copy_template_data(record), "record")
    if not isinstance(subsystem_id, str) or not subsystem_id.strip():
        raise AnsibleFilterError("subsystem_publish: id must be a non-empty string")
    current = _mapping(subsystems.get(subsystem_id, {}), "existing record")
    current.update(record)
    subsystems[subsystem_id] = current
    return subsystems


class FilterModule(object):
    def filters(self):
        return {"subsystem_publish": publish_subsystem}
