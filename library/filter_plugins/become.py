"""become_calc: resolve compfuzor's standard become/owner/group policy for a path.

Returns a dict ``{become, owner, group}`` computed once from:

  1. ``COMFUZOR_SHOULD_BECOME`` (if defined in scope)
  2. ``BECOME`` (if defined in scope)
  3. ``should_become(path, owner, _cf_user_id, group, _cf_user_gid)``

``owner`` / ``group`` resolve from the filter args (defaulting to scope
``OWNER`` / ``GROUP``) and fall back to ``_cf_user_id`` / ``_cf_user_gid``.
When ``become`` is false, ``owner`` / ``group`` are set to the Ansible
``Omit`` sentinel so ``file`` / ``template`` modules leave them unset.

Standard consumption pattern (see .design/null-defaults-pass/init.glm52.md):

    - name: ...
      file:
        path: "{{ _dir }}"
        owner: "{{ _become.owner }}"
        group: "{{ _become.group }}"
      become: "{{ _become.become }}"
      vars:
        _become: "{{ _dir|become_calc }}"
"""
from __future__ import absolute_import, division, print_function

__metaclass__ = type

from jinja2 import pass_context

try:  # pragma: no cover - exercised only under Ansible
    from ansible._internal._templating._utils import Omit as _Omit
except ImportError:  # standalone test fallback
    _Omit = "<<Omit>>"

try:
    from ansible.plugins.test.core import wrapped_test_undefined as _is_undefined
except ImportError:  # pragma: no cover - standalone fallback
    from jinja2 import Undefined

    def _is_undefined(value):
        return isinstance(value, Undefined)


def _present_truthy(scope, key):
    """Return (defined, truthy) for a scope key.

    ``defined`` is False when the key is absent or holds an Ansible-undefined
    marker (matching ``COMFUZOR_SHOULD_BECOME|default(...)`` without the
    ``true`` flag — only genuine absence or undefined falls through).
    """
    if key not in scope:
        return False, False
    value = scope[key]
    if _is_undefined(value):
        return False, False
    return True, bool(value)


def _present_value(scope, key):
    """Return (defined, value) for a scope key.

    ``defined`` is False when the key is absent, undefined, None, or empty
    string (matching ``OWNER|default(_cf_user_id, true)`` — the ``true`` flag
    means falsy values also fall through).
    """
    if key not in scope:
        return False, None
    value = scope[key]
    if _is_undefined(value) or value is None or value == "":
        return False, None
    return True, value


def _arg_value(arg):
    """Normalize a filter arg: None or undefined or empty → None (use scope)."""
    if arg is None or _is_undefined(arg) or arg == "":
        return None
    return arg


def resolve_become(scope, path, owner=None, group=None, should_become_fn=None):
    """Pure resolution logic — testable without Ansible context.

    Args:
        scope: dict with keys ``COMFUZOR_SHOULD_BECOME``, ``BECOME``,
            ``OWNER``, ``GROUP``, ``_cf_user_id``, ``_cf_user_gid`` (any may
            be absent).
        path: filesystem path the resolution is for.
        owner, group: explicit filter args overriding scope OWNER/GROUP. A
            None/undefined/empty arg means "defer to scope".
        should_become_fn: callable matching ``can_write.should_become``;
            defaults to the real one. Injected for testability.
    """
    if should_become_fn is None:  # pragma: no cover - lazy import for prod path
        from can_write import should_become as should_become_fn

    owner_arg = _arg_value(owner)
    group_arg = _arg_value(group)
    resolved_owner = owner_arg if owner_arg is not None else _present_value(scope, "OWNER")[1]
    resolved_group = group_arg if group_arg is not None else _present_value(scope, "GROUP")[1]
    cf_user_id = scope.get("_cf_user_id")
    cf_user_gid = scope.get("_cf_user_gid")

    defined, val = _present_truthy(scope, "COMFUZOR_SHOULD_BECOME")
    if defined:
        become = val
    else:
        defined, val = _present_truthy(scope, "BECOME")
        if defined:
            become = val
        else:
            become = bool(
                should_become_fn(path, resolved_owner, cf_user_id, resolved_group, cf_user_gid)
            )

    if become:
        owner_val = resolved_owner if resolved_owner is not None else cf_user_id
        group_val = resolved_group if resolved_group is not None else cf_user_gid
    else:
        owner_val = _Omit
        group_val = _Omit

    return {"become": become, "owner": owner_val, "group": group_val}


class FilterModule(object):
    @pass_context
    def become_calc(self, context, path, owner=None, group=None):
        # context.get_all() returns the full merged scope (play + role + task
        # vars) without touching the deprecated 'vars' dictionary magic.
        # Falls back to context.vars for older Jinja2 without get_all().
        get_all = getattr(context, "get_all", None)
        if callable(get_all):
            scope = get_all() or {}
        else:  # pragma: no cover - older Jinja2
            scope = context.vars or {}
        return resolve_become(scope, path, owner=owner, group=group)

    def filters(self):
        return {"become_calc": self.become_calc}
