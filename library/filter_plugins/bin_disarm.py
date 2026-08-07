"""Automatic disarm metadata and rendered-bin policy resolution.

``annotate_bins`` adds mergeable provenance and broad bypass-scope metadata to
manually aggregated BINS records. ``resolve_bin_disarm`` is the single policy
boundary used by ``files/_bin`` to turn that metadata, explicit ``bypass``, and
an optional TYPE fallback into effective shell guards and report text.
"""
from __future__ import annotations

import collections.abc
import os
import re
import sys

from ansible.errors import AnsibleFilterError
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from template_data import raw_copy_template_data  # noqa: E402


_NON_ALNUM = re.compile(r"[^A-Za-z0-9]+")


def _stable_dedupe(values):
    result = []
    for value in values:
        if value not in result:
            result.append(value)
    return result


def _is_absent(value):
    return wrapped_test_undefined(value) or value is None


def _canonical_tokens(value):
    if not isinstance(value, str):
        raise AnsibleFilterError(
            "bin disarm names and scopes must be strings; got {}".format(
                type(value).__name__
            )
        )
    return [token for token in _NON_ALNUM.sub("_", value).upper().split("_") if token]


def canonical_bin_action(name):
    """Canonicalize a rendered script name before scope-token subtraction."""
    if not isinstance(name, str):
        raise AnsibleFilterError(
            "bin disarm item name must be a string; got {}".format(
                type(name).__name__
            )
        )
    stem = os.path.basename(name)
    if stem.endswith(".sh"):
        stem = stem[:-3]
    stem = stem.split(".", 1)[0]
    return "_".join(_canonical_tokens(stem))


def _normalize_string_list(value, field):
    if _is_absent(value) or value is False:
        return []
    if isinstance(value, str):
        values = [value]
    elif isinstance(value, collections.abc.Sequence) and not isinstance(
        value, (str, bytes, bytearray)
    ):
        values = list(value)
    else:
        raise AnsibleFilterError(
            "bin disarm {} must be a string or list of strings; got {}".format(
                field, type(value).__name__
            )
        )
    if not all(isinstance(entry, str) for entry in values):
        raise AnsibleFilterError(
            "bin disarm {} must contain only strings".format(field)
        )
    return [entry for entry in values if entry]


def _canonical_scope(value):
    return "_".join(_canonical_tokens(value))


def _canonical_bypass_entry(value):
    concern, separator, unit = value.partition(":")
    concern = _canonical_scope(concern)
    if not concern:
        raise AnsibleFilterError("bin disarm bypass entries must name a concern")
    if not separator:
        return concern
    unit = _canonical_scope(unit)
    if not unit:
        raise AnsibleFilterError(
            "bin disarm unit bypass entries must name both concern and unit"
        )
    return "{}:{}".format(concern, unit)


@accept_args_markers
def annotate_bins(records, origin_subsystem, bypass_scope=None, subsystem=None):
    """Add disarm metadata to records from a manual BINS aggregation.

    Existing metadata is extended rather than replaced. ``subsystem`` remains
    an optional, independent compositor-grouping field.
    """
    records = raw_copy_template_data(records)
    if _is_absent(records):
        return []
    if isinstance(records, collections.abc.Mapping):
        records = [records]
    elif not isinstance(records, list):
        raise AnsibleFilterError(
            "annotate_bins expects a record or list of records; got {}".format(
                type(records).__name__
            )
        )

    origins = _normalize_string_list(origin_subsystem, "origin_subsystem")
    scopes = _normalize_string_list(
        origin_subsystem if _is_absent(bypass_scope) else bypass_scope,
        "bypass_scope",
    )
    result = []
    for record in records:
        if not isinstance(record, collections.abc.Mapping):
            result.append(record)
            continue
        annotated = dict(record)
        annotated["origin_subsystems"] = _stable_dedupe(
            _normalize_string_list(
                annotated.get("origin_subsystems"), "origin_subsystems"
            )
            + origins
        )
        annotated["bypass_scopes"] = _stable_dedupe(
            _normalize_string_list(annotated.get("bypass_scopes"), "bypass_scopes")
            + scopes
        )
        if not _is_absent(subsystem):
            annotated["subsystem"] = subsystem
        result.append(annotated)
    return result


@accept_args_markers
def resolve_bin_disarm(
    name,
    origin_subsystems=None,
    bypass_scopes=None,
    bypass=None,
    fallback_type=None,
):
    """Resolve automatic and explicit bypass policy for one rendered bin."""
    actual_name = os.path.basename(name) if isinstance(name, str) else name
    canonical_name = canonical_bin_action(name)
    origins = _stable_dedupe(
        _normalize_string_list(origin_subsystems, "origin_subsystems")
    )

    if bypass is False:
        return {
            "name": actual_name,
            "entries": [],
            "action": "",
            "verb": "running",
            "subsystems": origins,
            "report_labels": ", ".join(origins),
        }

    scopes = _normalize_string_list(bypass_scopes, "bypass_scopes")
    if not scopes and isinstance(name, str) and name.endswith(".sh"):
        scopes = _normalize_string_list(fallback_type, "fallback_type")
    canonical_scopes = _stable_dedupe(
        scope for scope in (_canonical_scope(value) for value in scopes) if scope
    )

    scope_tokens = {
        token for scope in canonical_scopes for token in scope.split("_") if token
    }
    action_tokens = [
        token
        for token in canonical_name.split("_")
        if token and token not in scope_tokens
    ]
    action = "_".join(action_tokens)

    automatic = []
    for scope in canonical_scopes:
        automatic.append(scope)
        if action:
            automatic.append("{}:{}".format(scope, action))
    explicit = [
        _canonical_bypass_entry(entry)
        for entry in _normalize_string_list(bypass, "bypass")
    ]
    entries = _stable_dedupe(automatic + explicit)
    verb = " ".join(token.lower() for token in action_tokens) or "running"
    return {
        "name": actual_name,
        "entries": entries,
        "action": action,
        "verb": verb,
        "subsystems": origins,
        "report_labels": ", ".join(origins),
    }


class FilterModule(object):
    def filters(self):
        return {
            "annotate_bins": annotate_bins,
            "canonical_bin_action": canonical_bin_action,
            "resolve_bin_disarm": resolve_bin_disarm,
        }
