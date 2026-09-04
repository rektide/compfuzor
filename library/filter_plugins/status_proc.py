"""Compile typed STATUS_PROC declarations into one provider contract."""

from __future__ import annotations

import collections.abc
import re

from ansible.errors import AnsibleFilterError
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
_ENV_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _error(message: str) -> None:
    raise AnsibleFilterError("status_proc_compile: {}".format(message))


def _mapping(value, label: str) -> dict:
    if not isinstance(value, collections.abc.Mapping):
        _error("{} must be a mapping".format(label))
    return dict(value)


def _validate_mainpid_env(row: dict) -> None:
    expected = row.get("expected")
    if not isinstance(expected, collections.abc.Mapping) or not expected:
        _error("STATUS_PROC mainpid-env requires a non-empty expected mapping")
    for key, expected_value in expected.items():
        if not isinstance(key, str) or not _ENV_NAME.fullmatch(key):
            _error(
                "STATUS_PROC mainpid-env contains an invalid environment variable name"
            )
        if not isinstance(expected_value, str):
            _error("STATUS_PROC mainpid-env expected values must be strings")


def _validate_exe_current(row: dict) -> None:
    expected = row.get("expected")
    if not isinstance(expected, str) or not expected.startswith("/"):
        _error("STATUS_PROC exe-current requires an absolute expected executable path")


_VALIDATORS = {
    "mainpid-env": _validate_mainpid_env,
    "exe-current": _validate_exe_current,
}


@accept_args_markers
def compile_status_proc(declarations, kinds, default_manager="system"):
    """Validate and normalize STATUS_PROC, then build its contributions."""
    kinds = _mapping(raw_copy_template_data(kinds), "STATUS_PROC kind registry")
    declarations = raw_copy_template_data(declarations)

    for check in kinds:
        if check not in _VALIDATORS:
            _error("STATUS_PROC kind '{}' has no validator".format(check))

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

        _VALIDATORS[check](row)

        row["manager"] = manager
        normalized.append(row)

    if not normalized:
        return {"spec": [], "contrib": {"BINS": [], "STATUSES": []}}

    bins = []
    statuses = []
    for check, raw_kind in kinds.items():
        selected = [row for row in normalized if row["check"] == check]
        if not selected:
            continue
        kind = _mapping(raw_kind, "STATUS_PROC kind '{}'".format(check))
        reporter = kind.get("reporter")
        source = kind.get("src")
        if not all(isinstance(value, str) and value for value in (reporter, source)):
            _error("STATUS_PROC kind '{}' is incomplete".format(check))

        bins.append(
            {
                "name": reporter,
                "src": source,
                "basedir": False,
                "bypass": "STATUS_PROC",
                "status_proc_checks": selected,
            }
        )
        statuses.append(reporter)

    return {
        "spec": normalized,
        "contrib": {"BINS": bins, "STATUSES": statuses},
    }


class FilterModule(object):
    def filters(self):
        return {"status_proc_compile": compile_status_proc}
