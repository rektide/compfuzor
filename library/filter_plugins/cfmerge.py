"""Compfuzor merge module — fixed pipeline for list, dict, and field merges.

The pipeline always executes ``collect -> normalize -> combine -> refine ->
extract``. A value preset fixes one normalizer, one combine, and its ordered
refines, so callers select documented behavior rather than composing arbitrary
transforms.

Before a public stage inspects a value, it crosses the shared non-rendering
template-data boundary. Lazy Ansible containers become ordinary containers,
while tagged template strings remain unevaluated for the later rendering phase.

Public Python API:
    ``normalize`` converts one raw value to a registered shape.
    ``collect`` applies top-level layer admission rules.
    ``run_value_preset`` executes the full pipeline for any value preset.
    ``merge_list`` and ``merge_dict`` constrain presets by result kind.
    ``merge_fields`` applies recursively nested field profiles.

The ``normalize``, ``merge_list``, ``merge_dict``, and ``merge_fields``
functions are all Ansible filters.
"""

from __future__ import absolute_import, division, print_function

import collections.abc
import os
import sys

from ansible.errors import AnsibleFilterError
from ansible.module_utils._internal._datatag import AnsibleTagHelper
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers

__all__ = [
    "COMBINES",
    "NORMALIZERS",
    "REFINES",
    "VALUE_PRESETS",
    "collect",
    "merge_dict",
    "merge_fields",
    "merge_list",
    "normalize",
    "run_value_preset",
    "value_preset_metadata",
]

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from get import get_path  # noqa: E402
from template_data import raw_copy_template_data  # noqa: E402


def _error(message):
    raise AnsibleFilterError(message)


def _is_undefined(value):
    return wrapped_test_undefined(value)


def _is_absent(value):
    return value is None or _is_undefined(value)


def _is_non_string_sequence(value):
    return isinstance(value, collections.abc.Sequence) and not isinstance(
        value, (str, bytes, bytearray)
    )


def _reject_options(stage, options):
    if options:
        _error(
            "{} does not accept option(s): {}".format(
                stage, ", ".join(sorted(options))
            )
        )


def _normalize_identity(value, **options):
    """Return a layer without changing its shape.

    This is the normalizer for a ``replace`` preset. In particular, ``None``
    and ``False`` remain data when collection does not suppress their layer.

    Args:
        value: Any raw layer value.
        **options: Unsupported; accepted only to share the registry signature.

    Returns:
        The original ``value``.

    Raises:
        AnsibleFilterError: If options were supplied.
    """
    _reject_options("identity normalizer", options)
    return value


def _normalize_list(value, **options):
    """Convert one optional contribution to a list.

    ``None``, Ansible undefined values, and literal ``False`` contribute an
    empty list. Lists, tuples, sets, and other non-string sequences are copied
    to a list. Every other value, including a mapping or string, becomes a
    single list item.

    Args:
        value: Raw layer value to normalize.
        **options: Unsupported; accepted only to share the registry signature.

    Returns:
        A new list representing this one layer.

    Raises:
        AnsibleFilterError: If options were supplied.
    """
    _reject_options("list normalizer", options)
    if _is_absent(value) or value is False:
        return []
    if isinstance(value, (list, tuple, set)) or _is_non_string_sequence(value):
        return list(value)
    return [value]


def _normalize_mapping(value, shorthand=False, **options):
    """Convert one optional contribution to a mapping.

    With ``shorthand=False``, only mappings are accepted. With
    ``shorthand=True``, a non-string sequence may additionally contain strings
    (expanded to ``{name: True}``) and mappings, overlaid left to right.
    ``None``, Ansible undefined values, and literal ``False`` contribute an
    empty mapping.

    Args:
        value: Raw layer value to normalize.
        shorthand: Whether to accept tool-version-style sequence shorthand.
        **options: Unsupported; accepted only to share the registry signature.

    Returns:
        A new dictionary for the layer.

    Raises:
        AnsibleFilterError: If the input or options are invalid.
    """
    _reject_options("mapping normalizer", options)
    if not isinstance(shorthand, bool):
        _error("mapping normalizer shorthand must be a boolean")

    if _is_absent(value) or value is False:
        return {}
    if isinstance(value, collections.abc.Mapping):
        return dict(value)
    if not shorthand or not _is_non_string_sequence(value):
        _error(
            "mapping normalizer expects a mapping{}; got {}".format(
                " or shorthand sequence" if shorthand else "",
                type(value).__name__,
            )
        )

    result = {}
    for item in value:
        if isinstance(item, str):
            result[item] = True
        elif isinstance(item, collections.abc.Mapping):
            result.update(dict(item))
        else:
            _error(
                "mapping shorthand entries must be strings or mappings; got {}".format(
                    type(item).__name__
                )
            )
    return result


def _normalize_items(value, key_name="key", value_name="value", **options):
    """Convert a mapping to item records, or preserve existing item records.

    A mapping becomes ``[{key_name: key, value_name: value}, ...]`` in mapping
    iteration order. A list, tuple, or set is copied to a list unchanged.
    ``None``, Ansible undefined values, and literal ``False`` contribute an
    empty item list.

    Args:
        value: Mapping or existing item-record collection.
        key_name: Field name for an emitted mapping key.
        value_name: Field name for an emitted mapping value.
        **options: Unsupported; accepted only to share the registry signature.

    Returns:
        A new item-record list.

    Raises:
        AnsibleFilterError: If field names, input, or options are invalid.
    """
    _reject_options("items normalizer", options)
    if not isinstance(key_name, str) or not key_name:
        _error("items normalizer key_name must be a non-empty string")
    if not isinstance(value_name, str) or not value_name:
        _error("items normalizer value_name must be a non-empty string")
    if _is_absent(value) or value is False:
        return []
    if isinstance(value, collections.abc.Mapping):
        return [{key_name: key, value_name: item} for key, item in value.items()]
    if isinstance(value, (list, tuple, set)):
        return list(value)
    _error(
        "items normalizer expects a mapping or list-like records; got {}".format(
            type(value).__name__
        )
    )


#: Registered normalizers, keyed by the public ``normalize(to=...)`` name.
#: Each callable receives one raw layer and returns the shape named by its key.
NORMALIZERS = {
    "identity": _normalize_identity,
    "list": _normalize_list,
    "mapping": _normalize_mapping,
    "items": _normalize_items,
}


@accept_args_markers
def normalize(value, *, to="list", **options):
    """Convert one raw value into a registered, bounded shape.

    This is shape conversion only: it does not merge multiple layers. Choose
    ``list`` for optional value-to-list conversion, ``mapping`` for strict or
    shorthand mappings, ``items`` for mapping-to-record conversion, or
    ``identity`` when the original shape must be preserved.

    Args:
        value: One raw value. ``None``, Ansible undefined values, and ``False``
            have normalizer-specific behavior.
        to: Registered normalizer name. Defaults to ``"list"``.
        **options: Options accepted by the selected normalizer. ``mapping``
            accepts ``shorthand``; ``items`` accepts ``key_name`` and
            ``value_name``.

    Returns:
        The converted value. Its shape is determined by ``to``.

    Raises:
        AnsibleFilterError: If ``to`` is unknown or its input/options are
            invalid.

    Examples:
        ``normalize("git")`` returns ``["git"]``.
        ``normalize(["rust", {"node": "22"}], to="mapping",
        shorthand=True)`` returns ``{"rust": True, "node": "22"}``.
        ``normalize({"/bin/tool": "src/tool"}, to="items",
        key_name="dest", value_name="src")`` returns a destination/source
        item record.
    """
    value = raw_copy_template_data(value)
    to = raw_copy_template_data(to)
    options = raw_copy_template_data(options)
    if not isinstance(to, str) or to not in NORMALIZERS:
        _error(
            "unknown normalizer {!r}; expected one of: {}".format(
                to, ", ".join(sorted(NORMALIZERS))
            )
        )
    return NORMALIZERS[to](value, **options)


_SKIP_CHECKS = {
    "none": lambda value: value is None,
    "undefined": _is_undefined,
    "false": lambda value: value is False,
    "empty": lambda value: isinstance(
        value,
        (
            str,
            bytes,
            bytearray,
            collections.abc.Sequence,
            collections.abc.Mapping,
            set,
            frozenset,
        ),
    )
    and len(value) == 0,
}
_DEFAULT_SKIP_LAYERS = ("none", "undefined")


def _require_layers(layers, name="layers"):
    if not isinstance(layers, (list, tuple)):
        _error("{} must be an explicit list or tuple of layers".format(name))
    return layers


def _parse_skip_layers(skip_layers):
    if isinstance(skip_layers, str) or not isinstance(
        skip_layers, (list, tuple, set, frozenset)
    ):
        _error("skip_layers must be a list, tuple, or set of skip predicates")
    names = frozenset(skip_layers)
    if "all" in names:
        return frozenset(_SKIP_CHECKS)
    unknown = names - frozenset(_SKIP_CHECKS)
    if unknown:
        _error(
            "unknown skip layer predicate(s): {}".format(
                ", ".join(sorted(str(name) for name in unknown))
            )
        )
    return names


def collect(layers, skip_layers=_DEFAULT_SKIP_LAYERS):
    """Keep top-level layers that do not match a requested skip predicate.

    Collection never descends into an admitted layer. For example, enabling the
    ``false`` predicate suppresses a layer equal to ``False`` but preserves
    ``[False]`` and ``["env", False]`` as data for the normalizer.

    The input first crosses the non-rendering template-data boundary. That
    materializes lazy containers safely; it is not semantic inspection of the
    layer contents.

    Args:
        layers: Explicit ordered list or tuple of whole contribution layers.
            When the entire input is ``None`` or Ansible undefined, ``collect``
            returns an empty list, letting the rest of the pipeline produce the
            preset identity.
        skip_layers: Names of predicates to apply: ``none``, ``undefined``,
            ``false``, and/or ``empty``. The default skips ``none`` and
            ``undefined`` only. Strings are deliberately rejected so callers
            cannot use the legacy comma-separated grammar.

    Returns:
        A new list of surviving raw layers in their original order.

    Raises:
        AnsibleFilterError: If layers are not explicit (and not absent), or
            predicate names are invalid.
    """
    layers = raw_copy_template_data(layers)
    if _is_absent(layers):
        return []
    skip_layers = raw_copy_template_data(skip_layers)
    surviving = []
    skip_names = _parse_skip_layers(skip_layers)
    for layer in _require_layers(layers):
        if any(_SKIP_CHECKS[name](layer) for name in skip_names):
            continue
        surviving.append(layer)
    return surviving


def _require_list_layers(layers, combine):
    for layer in layers:
        if not isinstance(layer, list):
            _error(
                "{} combine requires normalized list layers; got {}".format(
                    combine, type(layer).__name__
                )
            )


def _require_mapping_layers(layers, combine):
    for layer in layers:
        if not isinstance(layer, collections.abc.Mapping):
            _error(
                "{} combine requires normalized mapping layers; got {}".format(
                    combine, type(layer).__name__
                )
            )


def _concat(layers, **options):
    """Append normalized list layers in order without deduplicating."""
    _reject_options("concat combine", options)
    _require_list_layers(layers, "concat")
    result = []
    for layer in layers:
        result.extend(layer)
    return result


def _concat_strings_preserving_tags(left, right):
    combined = str(left) + "\n" + str(right)
    combined = AnsibleTagHelper.tag_copy(left, combined)
    return AnsibleTagHelper.tag_copy(right, combined)


def _keyed_fold(layers, key="key", concat_fields=(), **options):
    """Fold keyed record layers while preserving first keyed position.

    Later records replace ordinary fields. For ``concat_fields``, two lists are
    appended and two strings are newline-joined with their Ansible data tags
    preserved. Non-keyed values retain only their last occurrence.
    """
    _reject_options("keyed_fold combine", options)
    _require_list_layers(layers, "keyed_fold")
    if not isinstance(key, str) or not key:
        _error("keyed_fold key must be a non-empty string")
    if not isinstance(concat_fields, (list, tuple)) or not all(
        isinstance(field, str) and field for field in concat_fields
    ):
        _error("keyed_fold concat_fields must be a list or tuple of non-empty strings")

    keyed = {}
    non_keyed = []
    for layer in layers:
        for item in layer:
            if not isinstance(item, collections.abc.Mapping) or key not in item:
                if item in non_keyed:
                    non_keyed.remove(item)
                non_keyed.append(item)
                continue

            identifier = item[key]
            if identifier not in keyed:
                keyed[identifier] = dict(item)
                continue

            merged = keyed[identifier]
            for field, value in item.items():
                if field in concat_fields and field in merged:
                    existing = merged[field]
                    if isinstance(existing, list) and isinstance(value, list):
                        merged[field] = existing + value
                    elif isinstance(existing, str) and isinstance(value, str):
                        merged[field] = _concat_strings_preserving_tags(existing, value)
                    else:
                        merged[field] = value
                else:
                    merged[field] = value
    return list(keyed.values()) + non_keyed


def _union(layers, **options):
    """Overlay normalized mappings left to right, with later values winning."""
    _reject_options("union combine", options)
    _require_mapping_layers(layers, "union")
    result = {}
    for layer in layers:
        result.update(layer)
    return result


def _replace(layers, **options):
    """Return the last surviving layer, or ``None`` when none survived."""
    _reject_options("replace combine", options)
    return layers[-1] if layers else None


#: Registered folds. Each receives layers already normalized by a value preset.
COMBINES = {
    "concat": _concat,
    "keyed_fold": _keyed_fold,
    "union": _union,
    "replace": _replace,
}


def _contains_equal(values, candidate):
    return any(candidate == value for value in values)


def _dedupe(values, **options):
    """Return a stable first-seen deduplication using Python equality.

    This deliberately uses equality rather than hashing, so unhashable values
    such as mappings are supported and ``1`` compares equal to ``True``.
    """
    _reject_options("dedupe refine", options)
    result = []
    for value in values:
        if not _contains_equal(result, value):
            result.append(value)
    return result


def _dedupe_by(values, key="key", **options):
    """Keep a keyed record's first position but its last observed value."""
    _reject_options("dedupe_by refine", options)
    if not isinstance(key, str) or not key:
        _error("dedupe_by key must be a non-empty string")

    keys = []
    first_indices = []
    latest_records = []
    for index, value in enumerate(values):
        if not isinstance(value, collections.abc.Mapping) or key not in value:
            continue
        identifier = value[key]
        for key_index, known in enumerate(keys):
            if identifier == known:
                latest_records[key_index] = value
                break
        else:
            keys.append(identifier)
            first_indices.append(index)
            latest_records.append(value)

    result = []
    for index, value in enumerate(values):
        if not isinstance(value, collections.abc.Mapping) or key not in value:
            result.append(value)
            continue
        identifier = value[key]
        key_index = next(
            key_index
            for key_index, known in enumerate(keys)
            if identifier == known
        )
        if index == first_indices[key_index]:
            result.append(latest_records[key_index])
    return result


def _normalize_graph(graph):
    """Validate an implication graph and reject cycles before traversal."""
    if not isinstance(graph, collections.abc.Mapping):
        _error("implicate graph must be a mapping")
    normalized = {}
    for node, dependencies in graph.items():
        if not _is_non_string_sequence(dependencies):
            _error("implicate graph dependencies for {!r} must be a sequence".format(node))
        normalized[node] = list(dependencies)

    visiting = set()
    visited = set()

    def visit(node):
        if node in visited:
            return
        if node in visiting:
            _error("implicate graph contains a cycle at {!r}".format(node))
        visiting.add(node)
        for dependency in normalized[node]:
            dependency_key = _graph_key(normalized, dependency)
            if dependency_key is not None:
                visit(dependency_key)
        visiting.remove(node)
        visited.add(node)

    for node in normalized:
        visit(node)
    return normalized


def _graph_key(graph, candidate):
    for node in graph:
        if candidate == node:
            return node
    return None


def _implicate(values, graph, **options):
    """Add the transitive dependencies of selected graph nodes.

    Values not named by the graph are preserved unchanged. This makes the
    refine usable before a later policy chooses whether unknown values remain.
    """
    _reject_options("implicate refine", options)
    normalized_graph = _normalize_graph(graph)
    result = list(values)

    def add_dependencies(node):
        graph_key = _graph_key(normalized_graph, node)
        if graph_key is None:
            return
        for dependency in normalized_graph[graph_key]:
            if not _contains_equal(result, dependency):
                result.append(dependency)
            add_dependencies(dependency)

    for value in list(result):
        add_dependencies(value)
    return result


def _canonicalize(values, registry, drop_unknown, **options):
    """Order known values by a registry and apply its unknown-value policy."""
    _reject_options("canonicalize refine", options)
    if not _is_non_string_sequence(registry):
        _error("canonicalize registry must be a sequence")
    if not isinstance(drop_unknown, bool):
        _error("canonicalize drop_unknown must be a boolean")
    registry = list(registry)
    if len(_dedupe(registry)) != len(registry):
        _error("canonicalize registry must not contain duplicates")

    result = [entry for entry in registry if _contains_equal(values, entry)]
    if not drop_unknown:
        result.extend(
            value for value in values if not _contains_equal(registry, value)
        )
    return result


#: Registered immutable post-combine transforms, applied in preset order.
REFINES = {
    "dedupe": _dedupe,
    "dedupe_by": _dedupe_by,
    "implicate": _implicate,
    "canonicalize": _canonicalize,
}


#: Helper-specific implication policy used by the ``helpers`` value preset.
HELPER_IMPLICATIONS = {"report": ("loud",)}
#: Canonical helper emission order and allowed helper names.
HELPER_REGISTRY = ("env", "setopts", "loud", "report", "guard")


#: Fixed pipeline declarations keyed by public preset name.
#:
#: Every declaration has one ``normalizer``, one ``combine``, ordered
#: ``refines``, and a ``result_kind``. A configured preset has the form
#: ``{"name": "merge_keyed", "key": "name"}``; only options listed in a
#: stage's ``configurable`` tuple may be overridden.
VALUE_PRESETS = {
    "append": {
        "normalizer": {"name": "list"},
        "combine": {"name": "concat"},
        "refines": (),
        "result_kind": "list",
        "identity": [],
    },
    "append_unique": {
        "normalizer": {"name": "list"},
        "combine": {"name": "concat"},
        "refines": ({"name": "dedupe"},),
        "result_kind": "list",
        "identity": [],
    },
    "append_unique_by": {
        "normalizer": {"name": "list"},
        "combine": {"name": "concat"},
        "refines": ({"name": "dedupe_by", "options": {"key": "key"}, "configurable": ("key",)},),
        "result_kind": "list-record",
        "identity": [],
    },
    "merge_keyed": {
        "normalizer": {"name": "list"},
        "combine": {
            "name": "keyed_fold",
            "options": {"key": "key", "concat_fields": ()},
            "configurable": ("key", "concat_fields"),
        },
        "refines": (),
        "result_kind": "list-record",
        "identity": [],
    },
    "bins_generated": {
        "normalizer": {"name": "list"},
        "combine": {
            "name": "keyed_fold",
            "options": {
                "key": "name",
                "concat_fields": ("early", "generated", "run_all"),
            },
        },
        "refines": (),
        "result_kind": "list-record",
        "identity": [],
    },
    "overlay": {
        "normalizer": {"name": "mapping"},
        "combine": {"name": "union"},
        "refines": (),
        "result_kind": "mapping",
        "identity": {},
    },
    "tool_versions_overlay": {
        "normalizer": {"name": "mapping", "options": {"shorthand": True}},
        "combine": {"name": "union"},
        "refines": (),
        "result_kind": "mapping",
        "identity": {},
    },
    "replace": {
        "normalizer": {"name": "identity"},
        "combine": {"name": "replace"},
        "refines": (),
        "result_kind": "any",
        "identity": None,
    },
    "helpers": {
        "normalizer": {"name": "list"},
        "combine": {"name": "concat"},
        "refines": (
            {"name": "dedupe"},
            {"name": "implicate", "options": {"graph": HELPER_IMPLICATIONS}},
            {
                "name": "canonicalize",
                "options": {"registry": HELPER_REGISTRY, "drop_unknown": True},
            },
        ),
        "result_kind": "list",
        "identity": [],
    },
}


def _resolve_preset(preset):
    """Resolve a preset name/configuration to a private mutable execution plan.

    The returned nested dictionaries are copies, ensuring per-call configured
    options never mutate ``VALUE_PRESETS``.
    """
    preset = raw_copy_template_data(preset)
    if isinstance(preset, str):
        name = preset
        supplied_options = {}
    elif isinstance(preset, collections.abc.Mapping):
        name = preset.get("name")
        supplied_options = {key: value for key, value in preset.items() if key != "name"}
    else:
        _error("preset must be a preset name or a preset configuration mapping")

    if not isinstance(name, str) or name not in VALUE_PRESETS:
        _error(
            "unknown value preset {!r}; expected one of: {}".format(
                name, ", ".join(sorted(VALUE_PRESETS))
            )
        )

    definition = VALUE_PRESETS[name]
    configurable = set(definition["combine"].get("configurable", ()))
    for refine in definition["refines"]:
        configurable.update(refine.get("configurable", ()))
    unknown = set(supplied_options) - configurable
    if unknown:
        _error(
            "preset {!r} does not accept option(s): {}".format(
                name, ", ".join(sorted(unknown))
            )
        )

    normalizer = dict(definition["normalizer"])
    normalizer["options"] = dict(normalizer.get("options", {}))
    combine = dict(definition["combine"])
    combine["options"] = dict(combine.get("options", {}))
    for option in combine.get("configurable", ()):
        if option in supplied_options:
            combine["options"][option] = supplied_options[option]

    refines = []
    for refine_definition in definition["refines"]:
        refine = dict(refine_definition)
        refine["options"] = dict(refine.get("options", {}))
        for option in refine.get("configurable", ()):
            if option in supplied_options:
                refine["options"][option] = supplied_options[option]
        refines.append(refine)

    return {
        "name": name,
        "normalizer": normalizer,
        "combine": combine,
        "refines": refines,
        "result_kind": definition["result_kind"],
    }


def value_preset_metadata(preset):
    """Return a preset's result kind and a fresh combine identity.

    Lookup policies use this instead of restating whether an artifact is a list
    or mapping and what it should contribute when absent.

    Args:
        preset: Registered preset name or an allowed configuration mapping.

    Returns:
        A dictionary with the resolved preset ``name``, ``result_kind``, and a
        fresh ``identity`` value.

    Raises:
        AnsibleFilterError: If the preset is invalid.
    """
    resolved = _resolve_preset(preset)
    identity = VALUE_PRESETS[resolved["name"]]["identity"]
    if isinstance(identity, list):
        identity = list(identity)
    elif isinstance(identity, dict):
        identity = dict(identity)
    return {
        "name": resolved["name"],
        "result_kind": resolved["result_kind"],
        "identity": identity,
    }


def _run_resolved_value_preset(layers, resolved, skip_layers, get):
    """Execute a resolved preset without reinterpreting its configuration."""
    surviving = collect(layers, skip_layers=skip_layers)
    normalizer = resolved["normalizer"]
    normalized = [
        NORMALIZERS[normalizer["name"]](layer, **normalizer["options"])
        for layer in surviving
    ]
    combine = resolved["combine"]
    result = COMBINES[combine["name"]](normalized, **combine["options"])
    for refine in resolved["refines"]:
        result = REFINES[refine["name"]](result, **refine["options"])
    if get is not None:
        return get_path(result, raw_copy_template_data(get))
    return result


def run_value_preset(
    layers, *, preset, skip_layers=_DEFAULT_SKIP_LAYERS, get=None
):
    """Run the complete fixed pipeline for one value preset.

    The stages always occur in this order: collect top-level layers, normalize
    each survivor, combine the normalized values, apply the preset's refines,
    and optionally extract a dotted path. Preset configuration may only change
    explicitly configurable options such as ``merge_keyed``'s ``key`` and
    ``concat_fields``.

    Args:
        layers: Explicit ordered list or tuple of raw contribution layers.
        preset: A registered preset name or configuration mapping beginning with
            ``{"name": ...}``.
        skip_layers: Collection predicates. Defaults to skipping ``None`` and
            Ansible undefined layers; use ``("none", "undefined", "false")``
            to suppress a top-level ``False`` layer.
        get: Optional dotted path extracted from the final refined result.

    Returns:
        The preset result, or the extracted value when ``get`` is supplied.

    Raises:
        AnsibleFilterError: If layers, preset configuration, stage inputs, or
            extraction options are invalid.
    """
    return _run_resolved_value_preset(
        layers, _resolve_preset(preset), skip_layers, get
    )


def _merge_with_kind(layers, preset, skip_layers, get, allowed_kinds, operation):
    resolved = _resolve_preset(preset)
    if resolved["result_kind"] not in allowed_kinds:
        _error(
            "{} requires a {} preset; {!r} produces {}".format(
                operation,
                " or ".join(sorted(allowed_kinds)),
                resolved["name"],
                resolved["result_kind"],
            )
        )
    return _run_resolved_value_preset(
        layers, resolved, skip_layers, get
    )


@accept_args_markers
def merge_list(*layers, preset="append", skip_layers=_DEFAULT_SKIP_LAYERS, get=None):
    """Merge layers through a list-producing value preset.

    Each positional argument is one layer. A piped value is the first layer.

        {{ BINS | merge_list(incoming, preset='append') }}
        {{ merge_list(current, incoming, preset='append') }}

    Accepted result kinds are ``list`` and ``list-record``. The preset is
    always keyword-only — positional strategies are rejected. Absent layers
    (``None``, Ansible undefined) are skipped by the default collection
    predicates, so ``default()`` is not needed.

    Args:
        *layers: Ordered raw contribution layers. Each argument is one layer.
        preset: List-producing preset name or allowed configuration mapping.
        skip_layers: Top-level collection predicates.
        get: Optional dotted path extracted from the final result.

    Returns:
        A list result or an extracted value.

    Raises:
        AnsibleFilterError: If the preset is invalid or produces a non-list
            result.
    """
    return _merge_with_kind(
        layers,
        preset,
        skip_layers,
        get,
        {"list", "list-record"},
        "merge_list",
    )


@accept_args_markers
def merge_dict(*layers, preset="overlay", skip_layers=_DEFAULT_SKIP_LAYERS, get=None):
    """Merge layers through a mapping-producing value preset.

    Each positional argument is one layer. A piped value is the first layer.

        {{ ENV | merge_dict(incoming, preset='overlay') }}
        {{ merge_dict(current, incoming, preset='overlay') }}

    ``overlay`` uses strict mapping normalization, while
    ``tool_versions_overlay`` enables string-and-mapping shorthand. The preset
    is always keyword-only. Absent layers are skipped by default.

    Args:
        *layers: Ordered raw contribution layers. Each argument is one layer.
        preset: Mapping-producing preset name or allowed configuration mapping.
        skip_layers: Top-level collection predicates.
        get: Optional dotted path extracted from the final result.

    Returns:
        A mapping result or an extracted value.

    Raises:
        AnsibleFilterError: If the preset is invalid or produces a non-mapping
            result.
    """
    return _merge_with_kind(
        layers,
        preset,
        skip_layers,
        get,
        {"mapping"},
        "merge_dict",
    )


def _validate_profile(profile, path=""):
    """Validate the explicit leaf-or-branch grammar of a field profile."""
    if not isinstance(profile, collections.abc.Mapping):
        _error("field profile{} must be a mapping".format(" at " + path if path else ""))
    for field, specification in profile.items():
        field_path = "{}.{}".format(path, field) if path else str(field)
        if not isinstance(specification, collections.abc.Mapping):
            _error("field profile entry at {} must be a mapping".format(field_path))
        is_leaf = "preset" in specification
        is_branch = "fields" in specification
        if is_leaf == is_branch:
            _error(
                "field profile entry at {} must contain exactly one of preset or fields".format(
                    field_path
                )
            )
        expected_keys = {"preset"} if is_leaf else {"fields"}
        unknown = set(specification) - expected_keys
        if unknown:
            _error(
                "field profile entry at {} has unsupported key(s): {}".format(
                    field_path, ", ".join(sorted(str(key) for key in unknown))
                )
            )
        if is_leaf:
            _resolve_preset(specification["preset"])
        else:
            _validate_profile(specification["fields"], field_path)


def _merge_profile(records, profile, path=""):
    """Apply a prevalidated profile to records at one nesting level."""
    result = {}
    for field, specification in profile.items():
        field_path = "{}.{}".format(path, field) if path else str(field)
        if "preset" in specification:
            layers = [record[field] if field in record else None for record in records]
            result[field] = run_value_preset(layers, preset=specification["preset"])
            continue

        nested_records = []
        for record in records:
            if field not in record or _is_absent(record[field]):
                continue
            value = record[field]
            if not isinstance(value, collections.abc.Mapping):
                _error("field profile branch at {} requires mapping records".format(field_path))
            nested_records.append(value)
        result[field] = _merge_profile(
            nested_records, specification["fields"], field_path
        )
    return result


@accept_args_markers
def merge_fields(records, *, profile, get=None):
    """Merge prepared records using an explicit, recursively nested profile.

    Each profile entry has exactly one of two forms: ``{"preset": value}``
    merges the field values as layers through that value preset; ``{"fields":
    profile}`` recursively merges nested mapping records. Fields omitted by a
    record contribute ``None`` to leaves, which the default collection policy
    treats as absent.

    Args:
        records: Explicit ordered list or tuple of mapping records.
        profile: Field grammar made only from ``preset`` leaves and ``fields``
            branches. Presets may use the same name/configuration forms as
            ``run_value_preset``.
        get: Optional dotted path extracted from the completed field result.

    Returns:
        A mapping containing exactly the profile's fields, or an extracted
        value.

    Raises:
        AnsibleFilterError: If records, profile grammar, nested records, or
            referenced presets are invalid.

    Examples:
        ``merge_fields(records, profile={"ENV": {"preset": "overlay"}})``
        overlays the ``ENV`` field across prepared records.
        ``{"artifacts": {"fields": {"LINKS": {"preset": "append"}}}}``
        recursively appends ``artifacts.LINKS`` contributions.
    """
    records = raw_copy_template_data(records)
    profile = raw_copy_template_data(profile)
    get = raw_copy_template_data(get)
    _require_layers(records, name="records")
    for record in records:
        if not isinstance(record, collections.abc.Mapping):
            _error("merge_fields records must be mappings; got {}".format(type(record).__name__))
    _validate_profile(profile)
    result = _merge_profile(records, profile)
    if get is not None:
        return get_path(result, get)
    return result


class FilterModule(object):
    """Expose cfmerge filters to Ansible's filter-plugin loader."""

    def filters(self):
        return {
            "normalize": normalize,
            "merge_list": merge_list,
            "merge_dict": merge_dict,
            "merge_fields": merge_fields,
        }
