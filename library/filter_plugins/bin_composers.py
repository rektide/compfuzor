from __future__ import annotations

import collections.abc
import re

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import string_types
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


# The action set, as data. The composer is driven off this list, so extending
# the recognized actions (e.g. adding "status") is a one-line change here.
# `bin_composers(bins, actions=None)` also accepts an override list.
BIN_ACTIONS: tuple[str, ...] = ("build", "install", "apply")

# Ordered scheduling lanes for compositor `run_all`. Leaves sort by lane
# (stable: within a lane, BINS list order decides); an untagged bin is
# `main`, so all-untagged configurations render exactly as before. A
# subsystem compositor takes the earliest lane of its leaves.
BIN_PHASES: tuple[str, ...] = ("packages", "identity", "main", "units", "records")

_PHASE_INDEX = {p: i for i, p in enumerate(BIN_PHASES)}

# Suffix chars include `.` and `\` so systemd-escaped unit names (e.g.
# install-mount-mnt-...-RimWorld\x2djc141-files-.game\x2droot\x2dmnt.sh)
# classify as action leaves instead of falling out of the compositor
# hierarchy (they would never be wired into install-systemd.sh).
_ACTION_RE = re.compile(
    r"^(?P<action>" + "|".join(BIN_ACTIONS) + r")"
    r"(?P<suffix>-[A-Za-z0-9.\\][A-Za-z0-9._\\-]*)?"
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


def _resolve_phase(item):
    """A bin's `phase:` lane. Missing/None/False/empty means `main`;
    anything not in BIN_PHASES is an error (typos must fail loud, not
    silently render as main)."""
    phase = item.get("phase")
    if phase is None or phase is False or phase == "":
        return "main"
    if phase not in _PHASE_INDEX:
        raise AnsibleFilterError(
            "bin {!r} has unknown phase {!r}; expected one of {}".format(
                item.get("name"), phase, "/".join(BIN_PHASES)
            )
        )
    return phase


def _contributors(items):
    result = []
    for item in items:
        values = item.get("contributors", [])
        if isinstance(values, str):
            values = [values]
        for value in values:
            if isinstance(value, str) and value and value not in result:
                result.append(value)
    return result


def _item_contributors(item):
    values = item.get("contributors", [])
    if isinstance(values, str):
        return [values]
    if isinstance(values, collections.abc.Sequence) and not isinstance(values, (str, bytes)):
        return list(values)
    return []


@accept_args_markers
def partition_bin_states(bins):
    """Separate absent BINS tombstones from entries that should materialize."""
    present = []
    absent = []
    for item in _arrayitize(bins):
        target = (
            absent
            if isinstance(item, collections.abc.Mapping)
            and item.get("state") == "absent"
            else present
        )
        target.append(item)
    return {"present": present, "absent": absent}


@accept_args_markers
def bin_composers(bins, actions=None):
    """Build action compositors from explicitly named bin scripts.

    ``build*.sh``, ``install*.sh``, and ``apply*.sh`` (per ``BIN_ACTIONS``) are
    action scripts. Compositors form a two-tier hierarchy:

    * **Scope compositor** — the top entry point: ``<action>.sh`` (system) or
      ``<action>-user.sh`` (user). Always emitted when an action has leaves.
    * **Subsystem compositor** — ``<action>-<subsystem>[-user].sh``, emitted
      whenever a subsystem contributes a leaf to that (action, scope). The
      scope compositor invokes the subsystem compositor instead of those leaves
      directly.

    A bin declares its grouping via the ``subsystem`` field (auto-set by
    subsystem generators at contrib time, overridable by hand). Ungrouped bins
    (``subsystem`` absent/False) stay direct children of the scope compositor.

    ``action`` may explicitly classify a command independently of its filename;
    otherwise the historical filename grammar is used. ``scope`` accepts a
    string or list; install scripts ending in ``-user.sh`` infer the ``user``
    scope. The legacy ``.user.sh`` suffix remains accepted. ``compose: false``
    and already-generated compositors
    (``generated_by: gen_bins``) are excluded.

    ``phase`` is a scheduling lane from ``BIN_PHASES`` (default ``main``):
    leaves are stably sorted by lane before compositor assembly, so
    ``identity`` (account creation) precedes ``main`` (artifact installs),
    ``units`` (enable/start), and ``records`` (bookkeeping). A subsystem
    compositor lands in the earliest lane of its leaves. Lanes exist so
    ordering constraints live on the bin record rather than in task-file
    geography or merge-call flags; untagged configurations are unaffected.
    """
    if actions:
        _actions = tuple(actions)
        action_re = re.compile(
            r"^(?P<action>" + "|".join(_actions) + r")"
            r"(?P<suffix>-[A-Za-z0-9.\\][A-Za-z0-9._\\-]*)?"
            r"(?P<user>\.user)?\.sh$"
        )
    else:
        action_re = _ACTION_RE

    known_actions = _actions if actions else BIN_ACTIONS

    # Collect every authored action name for reservation checks, then retain
    # composing leaves with resolved (action, subsystem, scopes).
    authored_names: set[str] = set()
    leaves = []
    for item in _arrayitize(bins):
        if (
            not isinstance(item, collections.abc.Mapping)
            or item.get("state") == "absent"
            or item.get("generated_by") == "gen_bins"
        ):
            continue
        name = item.get("name")
        if not isinstance(name, string_types):
            continue
        match = action_re.match(name)
        explicit_action = item.get("action")
        if explicit_action is not None and explicit_action is not False and explicit_action != "":
            if not isinstance(explicit_action, string_types) or explicit_action not in known_actions:
                raise AnsibleFilterError(
                    "bin {!r} has unknown action {!r}; expected one of {}".format(
                        name, explicit_action, "/".join(known_actions)
                    )
                )
            action = explicit_action
        elif match:
            action = match.group("action")
        else:
            continue
        scopes = _arrayitize(item.get("scope"))
        if action == "install" and (
            name.startswith("install-user")
            or name.endswith("-user.sh")
            or (match and match.group("user"))
        ):
            scopes.append("user")
        scopes = list(dict.fromkeys(str(s) for s in scopes))
        scopes = scopes or [None]
        authored_names.add(name)
        if item.get("compose", True) is False:
            continue
        leaves.append(
            {
                "name": name,
                "action": action,
                "scopes": scopes,
                "subsystem": _resolve_subsystem(item.get("subsystem")),
                "phase": _resolve_phase(item),
                "contributors": _item_contributors(item),
            }
        )

    # Lane schedule: stable sort leaves by phase (BINS order within a lane).
    # This drives both subsystem-compositor run_all and scope-compositor
    # run_all, so `identity` leaves (sysusers) precede `main` artifact
    # installs, which precede `units` (enable/start), then `records`.
    leaves.sort(key=lambda lf: _PHASE_INDEX[lf["phase"]])

    # Bucket every (leaf, scope) by (action, subsystem, scope).
    sub_buckets: dict[tuple, list[str]] = {}
    for lf in leaves:
        for scope in lf["scopes"]:
            sub_buckets.setdefault(
                (lf["action"], lf["subsystem"], scope), []
            ).append(lf["name"])

    # Emit subsystem compositors for every real subsystem. Leaves so claimed
    # are pulled out of the scope compositor.
    claimed: set[tuple] = set()
    subsystem_compositors: dict[tuple, dict] = {}
    for (action, subsystem, scope), members in sub_buckets.items():
        if subsystem is None:
            continue
        for mem in members:
            claimed.add((mem, scope))
        comp_name = "{}-{}{}.sh".format(
            action, subsystem, f"-{scope}" if scope else ""
        )
        if comp_name in authored_names:
            raise AnsibleFilterError(
                "authored bin {!r} uses a reserved subsystem compositor name".format(
                    comp_name
                )
            )
        member_records = [lf for lf in leaves if lf["action"] == action and lf["subsystem"] == subsystem and scope in lf["scopes"]]
        compositor = {
            "name": comp_name,
            "action": action,
            "generated_by": "gen_bins",
            "run_all": list(members),
            "scope": [scope] if scope else [],
            # Compositors reference $DIR (env) and _cf_loud (loud) in their
            # run_all block, and want strict mode + restore (setopts); they
            # never call the _cf_action_*/guard primitives. Declare the need
            # so they stay correct even if DEFAULT_HELPERS is narrowed.
            "base_helpers": ["env", "setopts", "loud"],
        }
        contributors = _contributors(member_records)
        if contributors:
            compositor["contributors"] = contributors
        subsystem_compositors[(action, subsystem, scope)] = compositor

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
            "base_helpers": ["env", "setopts", "loud"],
        }
        contributors = _contributors([
            lf for lf in leaves if lf["action"] == action and scope in lf["scopes"]
        ])
        if contributors:
            compositor["contributors"] = contributors
        if scope:
            compositor["scope"] = [scope]
        compositors.append(compositor)

    return compositors


class FilterModule(object):
    def filters(self):
        return {
            "bin_composers": bin_composers,
            "partition_bin_states": partition_bin_states,
        }
