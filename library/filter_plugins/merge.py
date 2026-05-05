from __future__ import absolute_import, division, print_function

__metaclass__ = type

import os
import sys

from ansible.module_utils._internal._datatag import AnsibleTagHelper
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers
from jinja2 import pass_context

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from _subsystem_utils import _as_list, _dedupe_preserve  # noqa: E402
from get import get_path  # noqa: E402


LIST_STRATEGY_PROFILES = {
    "bins_generated": {
        "op": "merge_keyed",
        "key": "name",
        "concat_fields": ["generated"],
    },
}

VALID_LIST_STRATEGIES = {"append", "append_unique"}
VALID_LIST_OPERATIONS = {"append_unique_by", "merge_keyed"}


def _raw_copy_template_data(value):
    """Copy lazy Ansible containers without rendering tagged template strings."""
    if _is_nothing(value):
        return value

    non_lazy_copy = getattr(value, "_non_lazy_copy", None)
    if callable(non_lazy_copy):
        return _raw_copy_template_data(non_lazy_copy())

    if isinstance(value, dict):
        return {
            _raw_copy_template_data(k): _raw_copy_template_data(v)
            for k, v in dict.items(value)
        }

    if isinstance(value, list):
        return [_raw_copy_template_data(item) for item in list.__iter__(value)]

    if isinstance(value, tuple):
        return tuple(_raw_copy_template_data(item) for item in tuple.__iter__(value))

    return value


def _is_nothing(value):
    return value is None or wrapped_test_undefined(value)


def _dict_get_raw(mapping, key, default=None):
    if not isinstance(mapping, dict):
        return default
    try:
        return dict.__getitem__(mapping, key)
    except KeyError:
        return default


def _context_var_raw(context, name, default=None):
    variables = context.get("vars", {})
    return _dict_get_raw(variables, name, default=default)


def _truthy(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _resolve_list_strategy(strategy):
    if isinstance(strategy, str) and strategy in LIST_STRATEGY_PROFILES:
        return LIST_STRATEGY_PROFILES[strategy]
    return strategy


def _validate_list_strategy(strategy):
    if isinstance(strategy, str):
        if strategy not in VALID_LIST_STRATEGIES:
            raise ValueError("unknown merge_list strategy '{}'".format(strategy))
        return

    if isinstance(strategy, dict):
        op_name = strategy.get("op")
        if op_name not in VALID_LIST_OPERATIONS:
            raise ValueError("unknown merge_list operation '{}'".format(op_name))
        return

    raise ValueError(
        "merge_list strategy must be a string or dict, got {}".format(
            type(strategy).__name__
        )
    )


def _concat_strings_preserving_tags(left, right):
    combined = str(left) + "\n" + str(right)
    combined = AnsibleTagHelper.tag_copy(left, combined)
    combined = AnsibleTagHelper.tag_copy(right, combined)
    return combined


def _merge_keyed(left, right, key="key", concat_fields=None):
    if concat_fields is None:
        concat_fields = []

    merged_dict = {}
    non_dict_items = []

    for item in _as_list(left):
        if isinstance(item, dict) and key in item:
            merged_dict[item[key]] = item.copy()
        else:
            non_dict_items.append(item)

    for item in _as_list(right):
        if isinstance(item, dict) and key in item:
            key_value = item[key]
            if key_value in merged_dict:
                merged_item = merged_dict[key_value]
                for field, value in item.items():
                    if field in concat_fields and field in merged_item:
                        existing = merged_item[field]
                        if isinstance(value, list) and isinstance(existing, list):
                            merged_item[field] = existing + value
                        elif isinstance(value, str) and isinstance(existing, str):
                            merged_item[field] = _concat_strings_preserving_tags(
                                existing, value
                            )
                        else:
                            merged_item[field] = value
                    else:
                        merged_item[field] = value
            else:
                merged_dict[key_value] = item.copy()
        else:
            if item in non_dict_items:
                non_dict_items.remove(item)
            non_dict_items.append(item)

    return list(merged_dict.values()) + non_dict_items


def _append_unique_by(lists, key="key"):
    combined = []
    for value in lists:
        combined += _as_list(value)

    keyed = {}
    keyed_first_index = {}
    for i, item in enumerate(combined):
        if isinstance(item, dict) and key in item:
            key_val = item[key]
            keyed[key_val] = item
            if key_val not in keyed_first_index:
                keyed_first_index[key_val] = i

    result = []
    for i, item in enumerate(combined):
        if isinstance(item, dict) and key in item:
            key_val = item[key]
            if i == keyed_first_index[key_val]:
                result.append(keyed[key_val])
        else:
            result.append(item)

    return result


def _merge_list_values(values, strategy):
    if isinstance(strategy, str):
        combined = []
        for value in values:
            combined += _as_list(value)
        if strategy == "append_unique":
            return _dedupe_preserve(combined)
        return combined

    op_name = strategy.get("op")
    if op_name == "merge_keyed":
        result = []
        for value in values:
            result = _merge_keyed(
                result,
                value,
                key=strategy.get("key", "key"),
                concat_fields=strategy.get("concat_fields", []),
            )
        return result

    if op_name == "append_unique_by":
        return _append_unique_by(values, key=strategy.get("key", "key"))

    raise ValueError("unknown merge_list operation '{}'".format(op_name))


@accept_args_markers
def merge_list(values, strategy="append", single=False, get=None):
    """Merge direct list payloads with one list strategy.

    Default input shape is multiple payloads: [existing_list, incoming_list].
    Use single=True when the input value itself is one list payload.
    """
    values = _raw_copy_template_data(values)
    strategy = _raw_copy_template_data(_resolve_list_strategy(strategy))
    get = _raw_copy_template_data(get)
    _validate_list_strategy(strategy)

    if _is_nothing(values):
        payloads = []
    elif single:
        payloads = [values]
    else:
        payloads = _as_list(values)

    payloads = [value for value in payloads if not _is_nothing(value)]
    result = _merge_list_values(payloads, strategy)
    if get is not None:
        return get_path(result, get)
    return result


@pass_context
@accept_args_markers
def merge_list_subsys(
    context,
    current,
    subsystem_id=None,
    path="contrib.BINS",
    strategy="bins_generated",
    default=None,
    single=False,
    get=None,
    id=None,
    fallback_id=None,
    active=True,
    active_path="active",
):
    """Merge a current list with one list value from SUBSYSTEM.

    SUBSYSTEM is read through a raw-copy boundary so lazy template strings remain
    tagged and unevaluated during the merge.
    """
    current = _raw_copy_template_data(current)
    subsystem_id = _raw_copy_template_data(subsystem_id)
    id = _raw_copy_template_data(id)
    fallback_id = _raw_copy_template_data(fallback_id)
    path = _raw_copy_template_data(path)
    default = [] if default is None else _raw_copy_template_data(default)
    active = _raw_copy_template_data(active)
    active_path = _raw_copy_template_data(active_path)

    resolved_id = id if not _is_nothing(id) else subsystem_id
    if _is_nothing(resolved_id) or str(resolved_id).strip() == "":
        resolved_id = fallback_id

    incoming = default
    if not (_is_nothing(resolved_id) or str(resolved_id).strip() == ""):
        subsystems = _raw_copy_template_data(_context_var_raw(context, "SUBSYSTEM", {}))
        record = _dict_get_raw(subsystems, str(resolved_id).strip(), {})
        if (not active) or _truthy(get_path(record, active_path, default=False)):
            incoming = get_path(record, path, default=default)

    return merge_list([current, incoming], strategy=strategy, single=single, get=get)


class FilterModule(object):
    def filters(self):
        return {
            "merge_list": merge_list,
            "merge_list_subsys": merge_list_subsys,
        }
