from __future__ import absolute_import, division, print_function

__metaclass__ = type

from jinja2 import pass_context


def _context_var(context, name, default=None):
    all_vars = context.get("vars", {})
    if isinstance(all_vars, dict) and name in all_vars:
        return all_vars[name]

    inventory_hostname = context.get("inventory_hostname")
    hostvars = context.get("hostvars", {})
    if isinstance(hostvars, dict):
        host_values = hostvars.get(inventory_hostname, {})
        if isinstance(host_values, dict) and name in host_values:
            return host_values[name]

    return default


def _to_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _has_value(value):
    return value is not None and value != ""


def _normalize_bypass_var_name(name):
    if name is None:
        return None
    text = str(name).strip()
    if not text:
        return None
    normalized = text.upper().replace("-", "_")
    if not normalized.endswith("_BYPASS"):
        normalized = normalized + "_BYPASS"
    return normalized


def _dedupe(values):
    seen = set()
    result = []
    for value in values:
        if value is None:
            continue
        if value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def _effective_bypass_vars(subsystem, bypass_vars=None, domain=None):
    """Resolve effective bypass variable names for a subsystem.

    Rules:
    - defaults: subsystem-level + optional domain-level bypass vars
    - bypass_vars omitted/None: use defaults
    - bypass_vars True: use defaults
    - bypass_vars False: disable defaults (no bypass vars)
    - bypass_vars "true": use defaults
    - bypass_vars "SOME_VAR": explicit replacement
    - bypass_vars ["SOME_VAR"]: explicit replacement
    - bypass_vars [True, "SOME_VAR"]: defaults + explicit supplement
    """
    defaults = _dedupe(
        [
            _normalize_bypass_var_name(subsystem),
            _normalize_bypass_var_name(domain),
        ]
    )

    # No override configured: use automatic defaults.
    if bypass_vars is None:
        return defaults

    # Boolean override:
    # - True: keep defaults
    # - False: disable bypass resolution for this subsystem.
    if isinstance(bypass_vars, bool):
        return defaults if bypass_vars else []

    # String override:
    # - "true": keep defaults
    # - any other string: explicit replacement with one var.
    if isinstance(bypass_vars, str):
        if bypass_vars.strip().lower() == "true":
            return defaults
        explicit_name = _normalize_bypass_var_name(bypass_vars)
        return [explicit_name] if explicit_name else []

    # Sequence override:
    # - include True (or "true") to include defaults
    # - string tokens add explicit vars
    # - without True, explicit list is full replacement
    if isinstance(bypass_vars, (list, tuple, set)):
        include_defaults = False
        explicit = []
        for item in bypass_vars:
            if isinstance(item, bool):
                include_defaults = include_defaults or item
                continue
            if item is None:
                continue
            token = str(item).strip()
            lowered = token.lower()
            if lowered == "":
                continue
            if lowered == "true":
                include_defaults = True
                continue
            if lowered == "false":
                continue
            explicit.append(_normalize_bypass_var_name(token))
        base = defaults if include_defaults else []
        return _dedupe(base + explicit)

    # Unknown override type: fall back to safe defaults.
    return defaults


@pass_context
def owner_group_fields(context, row, owner=None, group=None):
    """Resolve owner/group fields with row-first precedence.

    Precedence:
    1. row.owner / row.group
    2. explicit owner/group arguments
    3. context OWNER/GROUP vars
    Empty values are dropped from the result.
    """
    if not isinstance(row, dict):
        row = {}

    default_owner = _context_var(context, "OWNER")
    default_group = _context_var(context, "GROUP")

    resolved_owner = row.get("owner", owner if owner is not None else default_owner)
    resolved_group = row.get("group", group if group is not None else default_group)

    result = {}
    if _has_value(resolved_owner):
        result["owner"] = resolved_owner
    if _has_value(resolved_group):
        result["group"] = resolved_group
    return result


@pass_context
def subsystem_bypass_vars(context, subsystem, bypass_vars=None, domain=None):
    """Return effective bypass variable names for a subsystem."""
    return _effective_bypass_vars(subsystem, bypass_vars=bypass_vars, domain=domain)


@pass_context
def subsystem_bypassed(context, subsystem, bypass_vars=None, domain=None):
    """Return True if any effective bypass variable resolves truthy."""
    bypass_names = _effective_bypass_vars(
        subsystem, bypass_vars=bypass_vars, domain=domain
    )
    for name in bypass_names:
        if _to_bool(_context_var(context, name, False)):
            return True
    return False


def _has_payload(value):
    if value is None:
        return False
    if isinstance(value, (list, tuple, set, dict)):
        return len(value) > 0
    return True


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, set):
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


def combine_with_strategy(
    records,
    strategies,
    aggregate=None,
    include_aggregate=True,
    payload_key=None,
):
    """Combine records using per-field merge strategies.

    Supported strategies:
    - append: extend list values as-is
    - append_unique: append list values, then stable-dedupe
    - dict_overlay: merge dicts where later values win
    - replace: replace with latest non-None value

    When `payload_key` is set and a record contains that key, the keyed payload
    is used. Otherwise the record itself is treated as payload.
    """
    strategy_map = _as_dict(strategies)
    combined = {}

    for field, strategy in strategy_map.items():
        if strategy in {"append", "append_unique"}:
            combined[field] = []
        elif strategy == "dict_overlay":
            combined[field] = {}
        else:
            combined[field] = None

    source_records = _as_list(records)
    if include_aggregate and isinstance(aggregate, dict):
        source_records = source_records + [aggregate]

    for record in source_records:
        if not isinstance(record, dict):
            continue

        payload = record
        if _has_value(payload_key):
            payload = record.get(payload_key, record)

        if not isinstance(payload, dict):
            continue

        for field, strategy in strategy_map.items():
            value = payload.get(field)

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

            if strategy == "replace":
                if value is not None:
                    combined[field] = value
                continue

            raise ValueError(
                "Unknown combine_with_strategy strategy for '{}': {}".format(
                    field, strategy
                )
            )

    return combined


def subsystem_rollup(children, aggregate=None, include_aggregate=True):
    """Roll up child subsystem contrib payloads into one aggregate payload.

    Inputs:
    - children: list of subsystem state records or contrib dicts
      - if a child has a `contrib` key, that value is used
      - otherwise, the child itself is treated as contrib
    - aggregate: optional all/aggregate contrib payload to overlay last
    - include_aggregate: include `aggregate` payload when truthy

    Output keys:
    - ETC_FILES, BINS, ENV, ENV_LIST, PKGS
    """
    return combine_with_strategy(
        children,
        {
            "ETC_FILES": "append",
            "BINS": "append",
            "ENV": "dict_overlay",
            "ENV_LIST": "append_unique",
            "PKGS": "append_unique",
        },
        aggregate=aggregate,
        include_aggregate=include_aggregate,
        payload_key="contrib",
    )


def build_install_bins(stem, basedir=False, src_root="../kernel"):
    """Return standard build/install bin entries for a stem.

    Example:
    - stem: "sysctl"
      -> build-sysctl.sh / install-sysctl.sh
    - stem: "kernel"
      -> build-kernel.sh / install-kernel.sh
    """
    stem_text = str(stem).strip()
    if not stem_text:
        return {"build_bins": [], "install_bins": []}

    return {
        "build_bins": [
            {
                "name": "build-{}.sh".format(stem_text),
                "src": "{}/build-{}.sh".format(src_root, stem_text),
                "basedir": basedir,
            }
        ],
        "install_bins": [
            {
                "name": "install-{}.sh".format(stem_text),
                "src": "{}/install-{}.sh".format(src_root, stem_text),
                "basedir": basedir,
            }
        ],
    }


@pass_context
def subsystem_record(
    context,
    subsystem,
    requested=None,
    bypassed=None,
    valid=None,
    errors=None,
    spec=None,
    contrib=None,
    status=None,
):
    """Build a subsystem runtime record with computed defaults.

    Purpose:
    - Keep subsystem state assembly consistent across tasks.
    - Avoid repeating base/status/active boilerplate in each subsystem block.

    Inclusion rules:
    - `spec` is attached only when valid + requested and payload is non-empty.
    - `contrib` is attached only when active and payload is non-empty.
    """
    resolved_errors = (
        errors if errors is not None else _context_var(context, "errors", [])
    )
    if resolved_errors is None:
        resolved_errors = []

    requested_bool = _to_bool(
        requested
        if requested is not None
        else _context_var(
            context, "_subsystem_requested", _context_var(context, "requested", False)
        )
    )
    bypassed_bool = _to_bool(
        bypassed
        if bypassed is not None
        else _context_var(
            context, "_subsystem_bypassed", _context_var(context, "bypassed", False)
        )
    )
    valid_bool = _to_bool(
        valid
        if valid is not None
        else _context_var(context, "_subsystem_valid", len(resolved_errors) == 0)
    )
    active_bool = requested_bool and (not bypassed_bool) and valid_bool

    resolved_status = (
        status if status is not None else _context_var(context, "_subsystem_status")
    )
    if resolved_status is None:
        if active_bool:
            resolved_status = "active"
        elif bypassed_bool:
            resolved_status = "bypassed"
        elif not valid_bool:
            resolved_status = "invalid"
        else:
            resolved_status = "requested"

    record = {
        "status": resolved_status,
        "requested": requested_bool,
        "bypassed": bypassed_bool,
        "valid": valid_bool,
        "active": active_bool,
        "reasons": resolved_errors,
    }

    if _has_value(subsystem):
        record["subsystem"] = subsystem

    if valid_bool and requested_bool and _has_payload(spec):
        record["spec"] = spec

    if active_bool and _has_payload(contrib):
        record["contrib"] = contrib

    return record


class FilterModule(object):
    def filters(self):
        return {
            "owner_group_fields": owner_group_fields,
            "subsystem_bypass_vars": subsystem_bypass_vars,
            "subsystem_bypassed": subsystem_bypassed,
            "subsystem_record": subsystem_record,
            "combine_with_strategy": combine_with_strategy,
            "subsystem_rollup": subsystem_rollup,
            "build_install_bins": build_install_bins,
        }
