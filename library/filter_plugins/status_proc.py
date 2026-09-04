"""Compile typed STATUS_PROC declarations into internal subsystem leaves."""

from __future__ import annotations

import collections.abc
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
_ENV_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _error(message: str) -> None:
    raise AnsibleFilterError("status_proc_publish: {}".format(message))


def _mapping(value, label: str) -> dict:
    if not isinstance(value, collections.abc.Mapping):
        _error("{} must be a mapping".format(label))
    return dict(value)


@accept_args_markers
def publish_status_proc(subsystems, declarations, kinds, default_manager="system"):
    """Validate STATUS_PROC and publish one subsystem leaf per present kind."""
    subsystems = _mapping(raw_copy_template_data(subsystems), "SUBSYSTEM")
    kinds = _mapping(raw_copy_template_data(kinds), "STATUS_PROC kind registry")
    declarations = raw_copy_template_data(declarations)

    if isinstance(declarations, (str, bytes)) or not isinstance(
        declarations, collections.abc.Sequence
    ):
        _error("STATUS_PROC must be a list of typed status checks")

    normalized = []
    names = set()
    for index, value in enumerate(declarations):
        row = _mapping(value, "STATUS_PROC[{}]".format(index))
        name = row.get("name")
        if not isinstance(name, str) or not _NAME.fullmatch(name):
            _error("STATUS_PROC entries require a unique lowercase name")
        if name in names:
            _error("STATUS_PROC entries require a unique lowercase name")
        names.add(name)

        check = row.get("check")
        if not isinstance(check, str) or check not in kinds:
            _error("STATUS_PROC entries require a known check")

        unit = row.get("unit")
        if not isinstance(unit, str) or not unit.endswith(".service") or not unit[:-8]:
            _error("STATUS_PROC checks require a concrete .service unit")

        manager = row.get("manager", default_manager)
        if manager not in ("system", "user"):
            _error("STATUS_PROC manager must resolve to system or user")

        expected = row.get("expected")
        if check == "mainpid-env":
            if not isinstance(expected, collections.abc.Mapping) or not expected:
                _error("STATUS_PROC mainpid-env requires a non-empty expected mapping")
            for key, expected_value in expected.items():
                if not isinstance(key, str) or not _ENV_NAME.fullmatch(key):
                    _error(
                        "STATUS_PROC mainpid-env contains an invalid environment variable name"
                    )
                if not isinstance(expected_value, str):
                    _error("STATUS_PROC mainpid-env expected values must be strings")
        elif check == "exe-current":
            if not isinstance(expected, str) or not expected.startswith("/"):
                _error(
                    "STATUS_PROC exe-current requires an absolute expected executable path"
                )

        row["manager"] = manager
        normalized.append(row)

    if not normalized:
        return subsystems

    provider = _mapping(subsystems.get("status_proc", {}), "SUBSYSTEM.status_proc")
    provider.update({"domain": "status", "requested": True, "spec": normalized})
    subsystems["status_proc"] = provider

    for check, raw_kind in kinds.items():
        selected = [row for row in normalized if row["check"] == check]
        if not selected:
            continue
        kind = _mapping(raw_kind, "STATUS_PROC kind '{}'".format(check))
        subsystem_id = kind.get("subsystem")
        reporter = kind.get("reporter")
        source = kind.get("src")
        if not all(isinstance(value, str) and value for value in (subsystem_id, reporter, source)):
            _error("STATUS_PROC kind '{}' is incomplete".format(check))

        leaf = _mapping(subsystems.get(subsystem_id, {}), "SUBSYSTEM.{}".format(subsystem_id))
        leaf.update(
            {
                "domain": "status",
                "requested": True,
                "spec": selected,
                "contrib": {
                    "BINS": [
                        {
                            "name": reporter,
                            "src": source,
                            "basedir": False,
                            "bypass": "STATUS_PROC",
                            "status_proc_checks": selected,
                        }
                    ],
                    "STATUSES": [reporter],
                },
            }
        )
        subsystems[subsystem_id] = leaf

    return subsystems


class FilterModule(object):
    def filters(self):
        return {"status_proc_publish": publish_status_proc}
