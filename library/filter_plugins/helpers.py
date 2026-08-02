from __future__ import annotations

import collections.abc
import os
import sys

from ansible.template import accept_args_markers

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from merge import merge_list  # noqa: E402


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

# Layers that are False / None / undefined contribute nothing. This is the
# `base_helpers: False` suppression convention, expressed as a merge_list skip.
_HELPER_SKIP = "false,none,undefined"


@accept_args_markers
def resolve_helpers(item, default_helpers=None):
    """Resolve the ordered list of helpers a bin should receive.

    Three layers, unioned (never overwritten) via ``merge_list(append_unique)``:

    * ``default_helpers`` (or ``DEFAULT_HELPERS``) — the global baseline.
    * ``item.base_helpers`` — the subsystem's contribution. ``False`` (or
      absent) suppresses this layer; a list/scalar merges in.
    * ``item.helpers`` — the author's add-on. ``False`` is the nuclear opt-out
      (no helpers at all = legacy ``no_header``); a list/scalar merges in.

    Then implications:

    * ``item.bypass`` set (and not False) implies ``report`` + ``guard``.
    * ``report`` present implies ``loud`` (report funcs read ``_cf_loud``).

    Finally reordered to canonical ``HELPERS`` order (deduped by merge_list).
    ``item.no_header`` true is treated as the nuclear opt-out for back-compat.
    """
    if not isinstance(item, collections.abc.Mapping):
        union = merge_list(
            [default_helpers if default_helpers is not None else DEFAULT_HELPERS],
            strategy="append_unique",
            skip=_HELPER_SKIP,
        )
        return [h for h in HELPERS if h in union]

    # Nuclear opt-out: helpers: False, or legacy no_header: true.
    if item.get("helpers") is False or item.get("no_header") is True:
        return []

    layers = [
        default_helpers if default_helpers is not None else DEFAULT_HELPERS,
        item.get("base_helpers"),
        item.get("helpers"),
    ]
    # Implication: bypass behavior needs report + guard. Added as its own layer
    # so merge_list dedupes it alongside the rest.
    bypass = item.get("bypass")
    if bypass is not False and bypass is not None:
        layers.append(["report", "guard"])

    union = merge_list(layers, strategy="append_unique", skip=_HELPER_SKIP)

    # Implication: report funcs read _cf_loud, so report pulls in loud.
    if "report" in union and "loud" not in union:
        union = list(union) + ["loud"]

    # Canonical order, filtered to the registry.
    return [h for h in HELPERS if h in union]


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
