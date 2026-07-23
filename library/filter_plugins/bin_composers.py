from __future__ import annotations

import collections.abc
import re

from ansible.module_utils.six import string_types
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


_ACTION_PATTERN = re.compile(
    r"^(?P<action>build|install)"
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


@accept_args_markers
def bin_composers(bins):
    """Build action compositor bins from explicitly named bin scripts.

    ``build*.sh`` and ``install*.sh`` are action scripts. An explicit ``scope``
    may be a string or list; one compositor is emitted for every declared scope.
    ``install-user.sh`` and ``install-*.user.sh`` infer the ``user`` scope.
    Compositors retain the canonical action filename and append child names through
    the shared ``run_all`` bin field.
    """
    groups = {}
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

        match = _ACTION_PATTERN.match(name)
        if not match:
            continue

        scopes = _arrayitize(item.get("scope"))
        if match.group("action") == "install" and (
            name.startswith("install-user") or match.group("user")
        ):
            scopes.append("user")
        scopes = list(dict.fromkeys(str(scope) for scope in scopes))

        target_scopes = scopes or [None]
        for scope in target_scopes:
            groups.setdefault((match.group("action"), scope), []).append(name)

    compositors = []
    for (action, scope), members in groups.items():
        scope_suffix = "" if scope is None else f"-{scope}"
        name = f"{action}{scope_suffix}.sh"
        run_all = [member for member in members if member != name]
        if not run_all:
            continue
        compositor = {
            "name": name,
            "action": action,
            "generated_by": "gen_bins",
            "run_all": run_all,
        }
        if scope is not None:
            compositor["scope"] = [scope]
        compositors.append(compositor)

    return compositors


class FilterModule(object):
    def filters(self):
        return {"bin_composers": bin_composers}
