from __future__ import absolute_import, division, print_function

__metaclass__ = type

import os
import sys

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from _subsystem_utils import _as_list, _as_dict, _dedupe_preserve
from get import get_path


def _merge_keyed(list1, list2, key="key", concat_fields=None):
    """Merge two lists of objects by key, preserving mergeKeyed behavior."""
    if not isinstance(list1, list):
        list1 = []
    if not isinstance(list2, list):
        list2 = []

    if concat_fields is None:
        concat_fields = []

    merged_dict = {}
    non_dict_items = []

    for item in list1:
        if isinstance(item, dict) and key in item:
            merged_dict[item[key]] = item.copy()
        else:
            non_dict_items.append(item)

    for item in list2:
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
                            merged_item[field] = existing + "\n" + value
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


def _strategy_operation_name(strategy):
    if isinstance(strategy, dict) and isinstance(strategy.get("op"), str):
        return strategy.get("op")
    return None


VALID_STRING_STRATEGIES = {"append", "append_unique", "dict_overlay", "replace"}
VALID_OPERATION_NAMES = {"append_unique_by", "merge_keyed"}

STRATEGY_PROFILES = {
    "subsystem_contrib": {
        "ETC_FILES": "append",
        "BINS": "append",
        "ENV": "dict_overlay",
        "ENV_LIST": "append_unique",
        "PKGS": "append_unique",
    },
    "subsystem_artifacts": {
        "ETC_FILES": "append",
        "LINKS": "append",
    },
    "bins_generated": {
        "BINS": {
            "op": "merge_keyed",
            "key": "name",
            "concat_fields": ["generated"],
        },
    },
}


def _resolve_strategies(strategies):
    if isinstance(strategies, str) and strategies in STRATEGY_PROFILES:
        return STRATEGY_PROFILES[strategies]
    return strategies


def _validate_strategies(strategies, path=""):
    """Validate the entire strategy map before any record processing.

    Recursively validates nested strategy maps.  Raises ValueError with
    a field path for any unknown strategy.
    """
    if not isinstance(strategies, dict):
        raise ValueError(
            "strategy map must be a dict, got {}{}".format(
                type(strategies).__name__,
                " at {}".format(path) if path else "",
            )
        )

    for field, strategy in strategies.items():
        field_path = "{}.{}".format(path, field) if path else field

        if isinstance(strategy, str):
            if strategy not in VALID_STRING_STRATEGIES:
                raise ValueError(
                    "unknown strategy '{}' at '{}'".format(strategy, field_path)
                )
        elif isinstance(strategy, dict):
            if "op" in strategy:
                op_name = strategy["op"]
                if op_name not in VALID_OPERATION_NAMES:
                    raise ValueError(
                        "unknown operation '{}' at '{}'".format(op_name, field_path)
                    )
            else:
                _validate_strategies(strategy, path=field_path)
        else:
            raise ValueError(
                "strategy must be a string or dict, got {} at '{}'".format(
                    type(strategy).__name__, field_path
                )
            )


def _strategy_initial_value(strategy):
    if isinstance(strategy, str):
        if strategy in {"append", "append_unique"}:
            return []
        if strategy == "dict_overlay":
            return {}
        # strategy == "replace"
        return None

    if isinstance(strategy, dict):
        op_name = _strategy_operation_name(strategy)
        if op_name in {"append_unique_by", "merge_keyed"}:
            return []
        # nested strategy map
        return {}


def _apply_strategy_operation(existing, value, strategy):
    op_name = _strategy_operation_name(strategy)
    if op_name == "merge_keyed":
        key = strategy.get("key", "key")
        concat_fields = strategy.get("concat_fields", [])
        return _merge_keyed(existing, value, key=key, concat_fields=concat_fields)

    if op_name == "append_unique_by":
        dedup_key = strategy.get("key", "key")
        combined = _as_list(existing) + _as_list(value)
        keyed = {}
        keyed_first_index = {}
        for i, item in enumerate(combined):
            if isinstance(item, dict) and dedup_key in item:
                key_val = item[dedup_key]
                keyed[key_val] = item
                if key_val not in keyed_first_index:
                    keyed_first_index[key_val] = i
        seen_keys = set()
        result = []
        for i, item in enumerate(combined):
            if isinstance(item, dict) and dedup_key in item:
                key_val = item[dedup_key]
                if i == keyed_first_index[key_val]:
                    result.append(keyed[key_val])
            else:
                result.append(item)
        return result

    raise ValueError(
        "Unknown merge_with_strategy operation strategy: {}".format(strategy)
    )


def _extract_payload_path(record, path):
    """Walk a dot-separated path into a dict.  Returns None on any failure."""
    if not isinstance(record, dict):
        return None
    current = record
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def merge_with_strategy(
    records,
    strategies,
    aggregate=None,
    include_aggregate=True,
    payload_path=None,
    into=None,
    single=False,
    get=None,
):
    """Merge records using per-field merge strategies.

    Supported strategies:
    - append: extend list values as-is
    - append_unique: append list values, then stable-dedupe
    - dict_overlay: merge dicts where later values win
    - replace: replace with latest non-None value
    - nested strategy map: recurse for a field using nested per-field strategies
    - operation strategy map (dict with `op`), currently:
      - {op: merge_keyed, key: name, concat_fields: [generated]}
      - {op: append_unique_by, key: name}
    - named profile string: use a predefined strategy map from STRATEGY_PROFILES
    - into: wrap input payloads into one strategy field before merging
    - single: with into, treat the whole input as one payload instead of multiple
    - get: extract a dotted path from the merged result; with into, extraction
      starts at the into field value

    Available profiles:
    - "subsystem_contrib": ETC_FILES append, BINS append, ENV dict_overlay,
      ENV_LIST append_unique, PKGS append_unique
    - "subsystem_artifacts": ETC_FILES append, LINKS append
    - "bins_generated": BINS merge_keyed by name, generated concat

    When `payload_path` is set, it is split on "." and walked into each record
    to extract the payload.  If any intermediate key is missing or the
    intermediate value is not a dict, the whole record is used as payload.
    """
    strategy_map = _as_dict(_resolve_strategies(strategies))
    _validate_strategies(strategy_map)
    combined = {}

    for field, strategy in strategy_map.items():
        combined[field] = _strategy_initial_value(strategy)

    if into is not None and str(into).strip() != "":
        into_field = str(into).strip()
        if into_field not in strategy_map:
            raise ValueError("into field '{}' is not present in strategy map".format(into_field))
        source_records = [records] if single else _as_list(records)
        source_records = [{into_field: record} for record in source_records]
    else:
        into_field = None
        source_records = _as_list(records)

    if include_aggregate and isinstance(aggregate, dict):
        aggregate_record = {into_field: aggregate} if into_field else aggregate
        source_records = source_records + [aggregate_record]

    for record in source_records:
        if not isinstance(record, dict):
            continue

        payload = record
        if payload_path is not None and payload_path != "":
            extracted = _extract_payload_path(record, payload_path)
            if extracted is not None:
                payload = extracted

        if not isinstance(payload, dict):
            continue

        for field, strategy in strategy_map.items():
            value = payload.get(field)

            if _strategy_operation_name(strategy):
                combined[field] = _apply_strategy_operation(
                    combined.get(field), value, strategy
                )
                continue

            if strategy == "append":
                combined[field] += _as_list(value)
                continue

            if strategy == "append_unique":
                combined[field] += _as_list(value)
                combined[field] = _dedupe_preserve(combined[field])
                continue

            if strategy == "dict_overlay":
                combined[field] = _as_dict(combined.get(field)) | _as_dict(value)
                continue

            if isinstance(strategy, dict):
                combined[field] = merge_with_strategy(
                    [combined.get(field), value],
                    strategy,
                    include_aggregate=False,
                )
                continue

            if strategy == "replace":
                if value is not None:
                    combined[field] = value
                continue

            raise ValueError(
                "Unknown merge_with_strategy strategy for '{}': {}".format(
                    field, strategy
                )
            )

    if into_field:
        result = combined.get(into_field, _strategy_initial_value(strategy_map[into_field]))
    else:
        result = combined

    if get is not None:
        return get_path(result, get)

    return result


class FilterModule(object):
    def filters(self):
        return {
            "merge_with_strategy": merge_with_strategy,
        }
