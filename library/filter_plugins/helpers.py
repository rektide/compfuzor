from __future__ import annotations

import collections.abc

from ansible.template import accept_args_markers


# Canonical emission order for bin helpers. Prologues emit in this order;
# epilogues in reverse. Order is fixed by the registry, NOT by request order,
# so that the setopts push always precedes loud's `set -x` (the push must
# capture pre-xtrace state for the footer restore to be correct).
HELPERS: tuple[str, ...] = ("env", "setopts", "loud", "report", "guard")

# Hardcoded one-line descriptions, emitted as `# <name> helper: <description>`
# before each inclusion by files/_bin.
HELPERS_DESCRIPTIONS: dict[str, str] = {
    "env": "default $DIR and source env.export",
    "setopts": "strict shell (errexit/nounset/pipefail) + nullglob, save/restore",
    "loud": "progress gate + xtrace at V>2",
    "report": "action progress + skip messaging",
    "guard": "guard evaluator + COMPFUZOR_*_BYPASS predicates",
}

DEFAULT_HELPERS: tuple[str, ...] = ("env", "setopts", "loud")


def _as_list(value):
    """Coerce a helper-field value to a list of names, or None when the field
    is absent/False/True (i.e. contributes no names). A scalar string becomes
    a single-element list, matching the arrayitize idiom used elsewhere."""
    if value is None or value is False or value is True:
        return None
    if isinstance(value, str):
        return [value]
    if isinstance(value, collections.abc.Sequence):
        return list(value)
    return None


@accept_args_markers
def resolve_helpers(item, default_helpers=None):
    """Resolve the ordered list of helpers a bin should receive.

    Three layers, unioned (never overwritten):

    * ``default_helpers`` (or ``DEFAULT_HELPERS``) — the global baseline.
    * ``item.base_helpers`` — the subsystem's contribution for this bin type.
      ``False`` suppresses this layer; a list/scalar merges in.
    * ``item.helpers`` — the author's add-on. ``False`` is the nuclear opt-out
      (no helpers at all, = legacy ``no_header``); a list/scalar merges in.

    Then implications:

    * ``item.bypass`` set (and not False) implies ``report`` + ``guard``.
    * ``report`` present implies ``loud`` (report funcs read ``_cf_loud``).

    Finally reorders to canonical ``HELPERS`` order (deduped).
    ``item.no_header`` true is treated as the nuclear opt-out for back-compat.
    """
    if default_helpers is None:
        default_helpers = list(DEFAULT_HELPERS)
    else:
        default_helpers = _as_list(default_helpers) or []

    if not isinstance(item, collections.abc.Mapping):
        return [h for h in HELPERS if h in default_helpers]

    # Nuclear opt-out: helpers: False, or legacy no_header: true.
    if item.get("helpers") is False or item.get("no_header") is True:
        return []

    resolved: list[str] = []

    def add(names):
        for n in names:
            if n in HELPERS and n not in resolved:
                resolved.append(n)

    add(default_helpers)

    base = item.get("base_helpers")
    if base is not False and base is not None:
        add(_as_list(base) or [])

    author = item.get("helpers")
    if author is not False and author is not None:
        add(_as_list(author) or [])

    # Implications: bypass behavior needs report + guard; report needs loud.
    bypass = item.get("bypass")
    if bypass is not False and bypass is not None:
        add(["report", "guard"])
    if "report" in resolved:
        add(["loud"])

    # Canonical order, deduped.
    return [h for h in HELPERS if h in resolved]


def helper_comment(name):
    """Format the ``# <name> helper: <description>`` line emitted before each
    helper inclusion in files/_bin."""
    desc = HELPERS_DESCRIPTIONS.get(name)
    if desc:
        return f"# {name} helper: {desc}"
    return f"# {name} helper"


class FilterModule(object):
    def filters(self):
        return {
            "resolve_helpers": resolve_helpers,
            "helper_comment": helper_comment,
        }
