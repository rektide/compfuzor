"""Common contributor-reference metadata for compiled artifact records."""

from __future__ import annotations

import collections.abc

from ansible.errors import AnsibleFilterError
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

from template_data import raw_copy_template_data


def _stable(values):
    result = []
    for value in values:
        if isinstance(value, str) and value and value not in result:
            result.append(value)
    return result


def _records(value, label):
    value = raw_copy_template_data(value)
    if value is None or value is False or wrapped_test_undefined(value):
        return []
    if isinstance(value, collections.abc.Mapping) or isinstance(value, str):
        return [value]
    if isinstance(value, collections.abc.Sequence) and not isinstance(value, (str, bytes)):
        return list(value)
    raise AnsibleFilterError("{} must be a record or list of records".format(label))


def contributor_references(deployment, subsystem=None, existing=None):
    if existing is None:
        references = []
    elif isinstance(existing, str):
        references = [existing]
    elif isinstance(existing, collections.abc.Sequence) and not isinstance(existing, (str, bytes)):
        references = list(existing)
    else:
        raise AnsibleFilterError("contributors must be a string or list of strings")
    if isinstance(deployment, str) and deployment:
        references.append("deployment:{}".format(deployment))
    if isinstance(subsystem, str) and subsystem:
        references.append("subsystem:{}".format(subsystem))
    return _stable(references)


@accept_args_markers
def attribute_bins(records, deployment, subsystem=None):
    output = []
    for raw in _records(records, "BINS"):
        if not isinstance(raw, collections.abc.Mapping):
            output.append(raw)
            continue
        record = dict(raw)
        origins = record.get("origin_subsystems", [])
        if isinstance(origins, str):
            origins = [origins]
        refs = contributor_references(deployment, subsystem, record.get("contributors", []))
        refs = _stable(refs + ["subsystem:{}".format(origin) for origin in origins])
        if refs:
            record["contributors"] = refs
        output.append(record)
    return output


@accept_args_markers
def attribute_statuses(records, deployment, subsystem=None, bins=None):
    bin_contributors = {}
    for item in _records(bins, "BINS"):
        if not isinstance(item, collections.abc.Mapping):
            continue
        name = item.get("dest", item.get("name"))
        if isinstance(name, str):
            bin_contributors[name] = _stable(
                bin_contributors.get(name, []) + item.get("contributors", [])
            )
    output = []
    by_id = {}
    for raw in _records(records, "STATUSES"):
        if isinstance(raw, str):
            record = {"id": "legacy:{}".format(raw), "name": raw}
        elif isinstance(raw, collections.abc.Mapping):
            record = dict(raw)
            name = record.get("name")
            if not isinstance(name, str) or not name:
                raise AnsibleFilterError("status records require a non-empty name")
            record.setdefault("id", "legacy:{}".format(name))
        else:
            raise AnsibleFilterError("STATUSES entries must be strings or mappings")
        if not isinstance(record.get("id"), str) or not record["id"]:
            raise AnsibleFilterError("status records require a non-empty string id")
        refs = contributor_references(deployment, subsystem, record.get("contributors", []))
        refs = _stable(refs + bin_contributors.get(record["name"], []))
        if refs:
            record["contributors"] = refs
        identity = record["id"]
        previous = by_id.get(identity)
        if previous is None:
            by_id[identity] = record
            output.append(record)
            continue
        comparable = {key: value for key, value in record.items() if key != "contributors"}
        prior_comparable = {key: value for key, value in previous.items() if key != "contributors"}
        if comparable != prior_comparable:
            raise AnsibleFilterError(
                "status id {!r} has conflicting invocations; assign explicit native ids".format(identity)
            )
        previous["contributors"] = _stable(
            previous.get("contributors", []) + record.get("contributors", [])
        )
    return output


@accept_args_markers
def attribute_links(records, deployment, subsystem=None):
    output = []
    for raw in _records(records, "LINKS"):
        if not isinstance(raw, collections.abc.Mapping):
            output.append(raw)
            continue
        record = dict(raw)
        refs = contributor_references(deployment, subsystem, record.get("contributors", []))
        if refs:
            record["contributors"] = refs
        output.append(record)
    return output


class FilterModule(object):
    def filters(self):
        return {
            "attribute_bins": attribute_bins,
            "attribute_statuses": attribute_statuses,
            "attribute_links": attribute_links,
        }
