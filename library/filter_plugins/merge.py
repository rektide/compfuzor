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

from get import get_path  # noqa: E402
from dictify import dictify  # noqa: E402


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, (tuple, set)):
        return list(value)
    return [value]


def _as_dict(value):
    if isinstance(value, dict):
        return value
    return {}


def _dedupe_preserve(values):
    result = []
    seen = set()
    for value in values:
        key = str(value)
        if key in seen:
            continue
        seen.add(key)
        result.append(value)
    return result


LIST_STRATEGY_PROFILES = {
    "bins_generated": {
        "op": "merge_keyed",
        "key": "name",
        "concat_fields": ["generated"],
    },
}

DICT_STRATEGY_PROFILES = {
    "env_overlay": "overlay",
    "tool_versions_overlay": "tool_versions_overlay",
}

VALID_LIST_STRATEGIES = {"append", "append_unique"}
VALID_LIST_OPERATIONS = {"append_unique_by", "merge_keyed"}
VALID_DICT_STRATEGIES = {"overlay", "dict_overlay", "tool_versions_overlay"}


def _raw_copy_template_data(value):
    """Copy lazy Ansible containers without rendering tagged template strings.

    Args:
        value: Any value passed from Ansible/Jinja. Lazy containers are copied
            through their modern ``_non_lazy_copy()`` hook before normal Python
            traversal happens.  ``_LazyValue`` instances are unwrapped via their
            ``.value`` property.

    Returns:
        A plain Python container tree where tagged strings remain tagged and
        unevaluated.
    """
    if _is_nothing(value):
        return value

    non_lazy_copy = getattr(value, "_non_lazy_copy", None)
    if callable(non_lazy_copy):
        return _raw_copy_template_data(non_lazy_copy())

    try:
        from ansible._internal._templating._lazy_containers import _LazyValue
        if isinstance(value, _LazyValue):
            return _raw_copy_template_data(value.value)
    except ImportError:
        pass

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
    """Read one dict key without calling lazy container accessors.

    Args:
        mapping: Candidate dictionary.
        key: Key to read.
        default: Value returned when `mapping` is not a dict or the key is absent.

    Returns:
        The raw dict value or `default`.
    """
    if not isinstance(mapping, dict):
        return default
    try:
        return dict.__getitem__(mapping, key)
    except KeyError:
        return default


def _context_var_raw(context, name, default=None):
    """Read one variable from a Jinja context without rendering sibling values.

    Args:
        context: Jinja pass_context object.
        name: Variable name to read from `context['vars']`.
        default: Value returned when the variable is absent.

    Returns:
        The raw variable value or `default`.
    """
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


def _resolve_dict_strategy(strategy):
    if isinstance(strategy, str) and strategy in DICT_STRATEGY_PROFILES:
        return DICT_STRATEGY_PROFILES[strategy]
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


def _validate_dict_strategy(strategy):
    if isinstance(strategy, str):
        if strategy not in VALID_DICT_STRATEGIES:
            raise ValueError("unknown merge_dict strategy '{}'".format(strategy))
        return

    raise ValueError(
        "merge_dict strategy must be a string, got {}".format(type(strategy).__name__)
    )


def _concat_strings_preserving_tags(left, right):
    """Concatenate two strings while preserving Ansible datatags.

    Args:
        left: Existing string value.
        right: Incoming string value.

    Returns:
        Newline-joined string with tags copied from both inputs where Ansible
        considers propagation safe.
    """
    combined = str(left) + "\n" + str(right)
    combined = AnsibleTagHelper.tag_copy(left, combined)
    combined = AnsibleTagHelper.tag_copy(right, combined)
    return combined


def _merge_keyed(left, right, key="key", concat_fields=None):
    """Merge two lists of dict records by a key field.

    Args:
        left: Existing list payload.
        right: Incoming list payload.
        key: Dict key used to identify overlapping records.
        concat_fields: Field names whose values should concatenate when records
            overlap. String concatenation preserves Ansible datatags.

    Returns:
        A merged list. For overlapping dict records, the incoming record wins
        except for fields listed in `concat_fields`.
    """
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
    """Append list payloads and keep the last dict for each key value.

    Args:
        lists: Sequence of list-like payloads.
        key: Dict key used to identify duplicates.

    Returns:
        A list preserving first key position while using the last matching dict
        value for each key.
    """
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
    """Merge already-normalized list payloads with a validated strategy.

    Args:
        values: List of list-like payloads to merge.
        strategy: Resolved list strategy string or operation dict.

    Returns:
        The merged list payload.
    """
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


def _merge_dict_values(values, strategy):
    """Merge already-normalized dict payloads with a validated strategy.

    Args:
        values: List of dict-like payloads to merge.
        strategy: Resolved dict strategy string. `overlay` and `dict_overlay`
            both mean later payloads win key conflicts.

    Returns:
        The merged dict payload.
    """
    if strategy in {"overlay", "dict_overlay"}:
        result = {}
        for value in values:
            result = result | _as_dict(value)
        return result

    if strategy == "tool_versions_overlay":
        result = {}
        for value in values:
            result = result | dictify(value)
        return result

    raise ValueError("unknown merge_dict strategy '{}'".format(strategy))


@accept_args_markers
def merge_list(values, strategy="append", single=False, get=None):
    """Merge direct list payloads with one list strategy.

    Args:
        values: List of payloads to merge. By default this is treated as multiple
            list payloads, for example `[existing_bins, incoming_bins]`.
        strategy: Strategy name or operation dict. Supported strings are
            `append`, `append_unique`, and named profiles such as
            `bins_generated`. Supported operation dicts use `op: merge_keyed` or
            `op: append_unique_by`.
        single: Treat `values` itself as one list payload instead of a list of
            payloads.
        get: Optional dotted path to extract from the merged result.

    Returns:
        The merged list, or the value at `get` when provided.
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


@accept_args_markers
def merge_dict(values, strategy="overlay", single=False, get=None):
    """Merge direct dict payloads with one dict strategy.

    Args:
        values: Dict payloads to merge. By default this is treated as multiple
            payloads, for example `[subsystem_env, existing_env]`.
        strategy: Strategy name. Supported strings are `overlay`, `dict_overlay`,
            and named profiles such as `env_overlay`. Overlay strategies merge
            left-to-right, so later payloads win key conflicts.
        single: Treat `values` itself as one dict payload instead of a list of
            payloads.
        get: Optional dotted path to extract from the merged result.

    Returns:
        The merged dict, or the value at `get` when provided.
    """
    values = _raw_copy_template_data(values)
    strategy = _raw_copy_template_data(_resolve_dict_strategy(strategy))
    get = _raw_copy_template_data(get)
    _validate_dict_strategy(strategy)

    if _is_nothing(values):
        payloads = []
    elif single:
        payloads = [values]
    else:
        payloads = _as_list(values)

    payloads = [value for value in payloads if not _is_nothing(value)]
    result = _merge_dict_values(payloads, strategy)
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

    Args:
        context: Jinja context supplied by `pass_context`.
        current: Existing list payload, usually a global artifact such as `BINS`.
        subsystem_id: Positional subsystem id. Ignored when `id` is provided.
        path: Dotted path inside the subsystem record to merge from. Defaults to
            `contrib.BINS`.
        strategy: Strategy name or operation dict passed to `merge_list`.
        default: Incoming payload used when the subsystem/path is absent or
            inactive. Defaults to an empty list.
        single: Forwarded to `merge_list`.
        get: Optional dotted path to extract from the merged result.
        id: Keyword subsystem id. Preferred when call sites need explicit naming.
        fallback_id: Subsystem id used when `id`/`subsystem_id` is absent or empty.
        active: When truthy, merge only if the subsystem's `active_path` is truthy.
        active_path: Dotted path used for active gating. Defaults to `active`.

    Returns:
        The merged list, or the value at `get` when provided.
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


@pass_context
@accept_args_markers
def merge_dict_subsys(
    context,
    current,
    subsystem_id=None,
    path="contrib.ENV",
    strategy="env_overlay",
    default=None,
    single=False,
    get=None,
    id=None,
    fallback_id=None,
    active=True,
    active_path="active",
    current_wins=True,
):
    """Merge a current dict with one dict value from SUBSYSTEM.

    SUBSYSTEM is read through a raw-copy boundary so lazy template strings remain
    tagged and unevaluated during the merge.

    Args:
        context: Jinja context supplied by `pass_context`.
        current: Existing dict payload, usually a global artifact such as `ENV`.
        subsystem_id: Positional subsystem id. Ignored when `id` is provided.
        path: Dotted path inside the subsystem record to merge from. Defaults to
            `contrib.ENV`.
        strategy: Strategy name passed to `merge_dict`.
        default: Incoming payload used when the subsystem/path is absent or
            inactive. Defaults to an empty dict.
        single: Forwarded to `merge_dict`.
        get: Optional dotted path to extract from the merged result.
        id: Keyword subsystem id. Preferred when call sites need explicit naming.
        fallback_id: Subsystem id used when `id`/`subsystem_id` is absent or empty.
        active: When truthy, merge only if the subsystem's `active_path` is truthy.
        active_path: Dotted path used for active gating. Defaults to `active`.
        current_wins: When truthy, current/global values override subsystem
            values. This preserves existing ENV synthesis behavior.

    Returns:
        The merged dict, or the value at `get` when provided.
    """
    current = _raw_copy_template_data(current)
    subsystem_id = _raw_copy_template_data(subsystem_id)
    id = _raw_copy_template_data(id)
    fallback_id = _raw_copy_template_data(fallback_id)
    path = _raw_copy_template_data(path)
    default = {} if default is None else _raw_copy_template_data(default)
    active = _raw_copy_template_data(active)
    active_path = _raw_copy_template_data(active_path)
    current_wins = _raw_copy_template_data(current_wins)

    resolved_id = id if not _is_nothing(id) else subsystem_id
    if _is_nothing(resolved_id) or str(resolved_id).strip() == "":
        resolved_id = fallback_id

    incoming = default
    if not (_is_nothing(resolved_id) or str(resolved_id).strip() == ""):
        subsystems = _raw_copy_template_data(_context_var_raw(context, "SUBSYSTEM", {}))
        record = _dict_get_raw(subsystems, str(resolved_id).strip(), {})
        if (not active) or _truthy(get_path(record, active_path, default=False)):
            incoming = get_path(record, path, default=default)

    payloads = [incoming, current] if _truthy(current_wins) else [current, incoming]
    return merge_dict(payloads, strategy=strategy, single=single, get=get)


class FilterModule(object):
    def filters(self):
        return {
            "merge_dict": merge_dict,
            "merge_dict_subsys": merge_dict_subsys,
            "merge_list": merge_list,
            "merge_list_subsys": merge_list_subsys,
        }
