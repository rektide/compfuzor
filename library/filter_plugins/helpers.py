from __future__ import annotations

import os
import sys

from ansible.template import accept_args_markers

_PLUGIN_DIR = os.path.abspath(os.path.dirname(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from merge_pipeline import run_value_preset  # noqa: E402

# Hardcoded one-line descriptions, emitted as `# <name> helper: <description>`
# before each inclusion by files/_bin.
HELPERS_DESCRIPTIONS: dict[str, str] = {
    "env": "default $DIR and source env.export",
    "setopts": "strict shell (errexit/nounset/pipefail) + nullglob, save/restore",
    "loud": "progress gate + xtrace at V>2",
    "report": "action progress + skip messaging",
    "guard": "guard evaluator + COMPFUZOR_*_BYPASS predicates",
}

@accept_args_markers
def resolve_helpers(layers):
    """Resolve caller-prepared helper layers through the ``helpers`` preset.

    The caller owns field policy: default helpers, ``base_helpers``, bypass
    implications, author helpers, and the nuclear ``helpers: false`` branch.
    This filter only applies the central fixed preset: concatenate, dedupe,
    imply dependencies, and canonicalize allowed helper names.

    Args:
        layers: Explicit ordered helper layers. Top-level ``False``, ``None``,
            and Ansible undefined values contribute nothing.

    Returns:
        Canonically ordered helper names.
    """
    return run_value_preset(
        layers,
        preset="helpers",
        skip_layers=("none", "undefined", "false"),
    )


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
