from __future__ import annotations

import collections.abc
import re

from ansible.module_utils.six import string_types
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


# The action set, as data. The composer is driven off this list, so extending
# the recognized actions (e.g. adding "status") is a one-line change here.
# `bin_composers(bins, actions=None)` also accepts an override list.
BIN_ACTIONS: tuple[str, ...] = ("build", "install", "apply")

_ACTION_RE = re.compile(
    r"^(?P<action>" + "|".join(BIN_ACTIONS) + r")"
    r"(?P<suffix>-[A-Za-z0-9][A-Za-z0-9_-]*)?"
    r"(?P<user>\.user)?\.sh$"
)


def _arrayitize(value):
    if (
        wrapped_test_undefined(value)
        or value is None
        or value is False
        or value is True
    ):
        return []
    if isinstance(value, string_types):
        return [value]
    if isinstance(value, collections.abc.Sequence):
        return list(value)
    return [value]


def _resolve_subsystem(value):
    """A bin's `subsystem:` field: a non-empty string names a grouping;
    False/None/empty/missing means ungrouped (direct child of the scope
    compositor)."""
    if value is False or value is None or value == "":
        return None
    return str(value)


@accept_args_markers
def bin_composers(bins, actions=None):
    """Build action compositors from explicitly named bin scripts.

    ``build*.sh``, ``install*.sh``, and ``apply*.sh`` (per ``BIN_ACTIONS``) are
    action scripts. Compositors form a two-tier hierarchy:

    * **Scope compositor** — the top entry point: ``<action>.sh`` (system) or
      ``<action>-user.sh`` (user). Always emitted when an action has leaves.
    * **Subsystem compositor** — ``<action>-<subsystem>[-user].sh``, emitted
      only when a subsystem contributes >=2 leaves to that (action, scope).
      The scope compositor invokes the subsystem compositor instead of those
      leaves directly.

    A bin declares its grouping via the ``subsystem`` field (auto-set by
    subsystem generators at contrib time, overridable by hand). Ungrouped bins
    (``subsystem`` absent/False) stay direct children of the scope compositor.

    ``scope`` accepts a string or list; ``install-user.sh`` and
    ``install-*.user.sh`` infer the ``user`` scope. ``compose: false`` and
    already-generated compositors (``generated_by: gen_bins``) are excluded.
    """
    if actions:
        _actions = tuple(actions)
        action_re = re.compile(
            r"^(?P<action>" + "|".join(_actions) + r")"
            r"(?P<suffix>-[A-Za-z0-9][A-Za-z0-9_-]*)?"
            r"(?P<user>\.user)?\.sh$"
        )
    else:
        action_re = _ACTION_RE

    # Collect action leaves with resolved (action, subsystem, scopes).
    leaves = []
    for item in _arrayitize(bins):
        if (
            not isinstance(item, collections.abc.Mapping)
            or item.get("generated_by") == "gen_bins"
            or item.get("compose", True) is False
        ):
            continue
        name = item.get("name")
        if not isinstance(name, string_types):
            continue
        match = action_re.match(name)
        if not match:
            continue
        scopes = _arrayitize(item.get("scope"))
        if match.group("action") == "install" and (
            name.startswith("install-user") or match.group("user")
        ):
            scopes.append("user")
        scopes = list(dict.fromkeys(str(s) for s in scopes))
        leaves.append(
            {
                "name": name,
                "action": match.group("action"),
                "scopes": scopes or [None],
                "subsystem": _resolve_subsystem(item.get("subsystem")),
            }
        )

    # Bucket every (leaf, scope) by (action, subsystem, scope).
    sub_buckets: dict[tuple, list[str]] = {}
    for lf in leaves:
        for scope in lf["scopes"]:
            sub_buckets.setdefault(
                (lf["action"], lf["subsystem"], scope), []
            ).append(lf["name"])

    # Emit subsystem compositors for groups with >=2 leaves and a real
    # subsystem. Leaves so claimed are pulled out of the scope compositor.
    claimed: set[tuple] = set()
    subsystem_compositors: dict[tuple, dict] = {}
    for (action, subsystem, scope), members in sub_buckets.items():
        if subsystem is None or len(members) < 2:
            continue
        for mem in members:
            claimed.add((mem, scope))
        comp_name = "{}-{}{}.sh".format(
            action, subsystem, f"-{scope}" if scope else ""
        )
        subsystem_compositors[(action, subsystem, scope)] = {
            "name": comp_name,
            "action": action,
            "generated_by": "gen_bins",
            "run_all": [m for m in members if m != comp_name],
            "scope": [scope] if scope else [],
        }

    # Build scope compositors in BINS order. Each claimed leaf contributes its
    # subsystem compositor (once); unclaimed leaves contribute themselves.
    scope_groups: dict[tuple, list[str]] = {}
    added_sub: set[tuple] = set()
    for lf in leaves:
        for scope in lf["scopes"]:
            bucket = scope_groups.setdefault((lf["action"], scope), [])
            if (lf["name"], scope) in claimed:
                key = (lf["action"], lf["subsystem"], scope)
                if key not in added_sub:
                    added_sub.add(key)
                    bucket.append(subsystem_compositors[key]["name"])
            else:
                bucket.append(lf["name"])

    compositors = list(subsystem_compositors.values())
    for (action, scope), members in scope_groups.items():
        scope_name = "{}{}.sh".format(action, f"-{scope}" if scope else "")
        run_all = [m for m in members if m != scope_name]
        seen: set[str] = set()
        run_all = [m for m in run_all if not (m in seen or seen.add(m))]
        if not run_all:
            continue
        compositor = {
            "name": scope_name,
            "action": action,
            "generated_by": "gen_bins",
            "run_all": run_all,
        }
        if scope:
            compositor["scope"] = [scope]
        compositors.append(compositor)

    return compositors


class FilterModule(object):
    def filters(self):
        return {"bin_composers": bin_composers}
