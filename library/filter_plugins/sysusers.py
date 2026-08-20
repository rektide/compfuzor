"""sysusers_render: render SYSUSERS specs into a sysusers.d(5) fragment body.

Design: .design/gen-user/init.md. One fragment per playbook (DIR/etc/
sysusers.d/NAME.conf). Line kinds:

* ``u`` declares a user (implicitly creates the same-name primary group)
* ``g`` declares a group
* ``m`` adds a user to a group (implicitly creates missing names, which makes
  consumers of shared groups standalone-safe)

Declaration semantics per sysusers.d(5): a name is ``u``/``g``-declared in
exactly one fragment (duplicates warn, earliest filename wins), while ``m``
lines may appear anywhere. Rendered output is normalized to dependency-safe
order (``g``, then ``u``, then ``m``) regardless of authoring order.

Spec forms:

* ``apt-cacher-rs`` (string) -- user with defaults
* ``{name: media, kind: group}`` -- group declaration
* ``{name: sonarr, member: media}`` -- membership (consume)
* ``{name: gitea, comment: ..., home: ..., shell: ..., id: ...}`` -- overrides

Same-name ``u`` (or ``g``) specs: the later one wins outright -- derived
entries are prepended by gen_sysusers.tasks so authored specs override them.
Identical ``m`` lines dedupe; differing memberships for the same pair are a
sysusers-level concern, not rendered away.
"""
from __future__ import absolute_import, division, print_function

__metaclass__ = type

import re

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import string_types

try:
    from ansible.plugins.test.core import wrapped_test_undefined as _is_undefined
except ImportError:  # pragma: no cover - standalone fallback
    from jinja2 import Undefined

    def _is_undefined(value):
        return isinstance(value, Undefined)


DEFAULT_HOME = "/nonexistent"
DEFAULT_SHELL = "/usr/sbin/nologin"

# sysusers.d(5): valid user/group names on the system
_NAME_RE = re.compile(r"^[a-zA-Z0-9_.][a-zA-Z0-9_.-]*\$?$")

_KINDS = ("user", "group", "member")


def _arrayitize(value):
    if _is_undefined(value) or value is None or value is False or value is True:
        return []
    if isinstance(value, string_types):
        return [value]
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def _require_name(spec, name):
    if not isinstance(name, string_types) or not name:
        raise AnsibleFilterError(
            "sysusers spec {!r} needs a non-empty string name".format(spec)
        )
    if not _NAME_RE.match(name):
        raise AnsibleFilterError(
            "sysusers name {!r} is not a valid user/group name".format(name)
        )


def _quote_gecos(text):
    # GECOS-style comment field: double-quoted, escape backslash and quote.
    return '"{}"'.format(str(text).replace("\\", "\\\\").replace('"', '\\"'))


def _user_line(spec):
    name = spec.get("name")
    _require_name(spec, name)
    comment = spec.get("comment", name)
    home = spec.get("home", DEFAULT_HOME)
    shell = spec.get("shell", DEFAULT_SHELL)
    uid = spec.get("id", "-")
    for field, value in (("home", home), ("shell", shell)):
        if not isinstance(value, string_types) or not value.startswith("/"):
            raise AnsibleFilterError(
                "sysusers spec {!r}: {} must be an absolute path, got {!r}".format(
                    name, field, value
                )
            )
    return "u {} {} {} {} {}".format(name, uid, _quote_gecos(comment), home, shell)


def _group_line(spec):
    name = spec.get("name")
    _require_name(spec, name)
    return "g {} {}".format(name, spec.get("id", "-"))


def _member_line(spec):
    name = spec.get("name")
    _require_name(spec, name)
    group = spec.get("member", spec.get("group"))
    if not isinstance(group, string_types) or not group:
        raise AnsibleFilterError(
            "sysusers membership spec {!r} needs a group (member: <group>)".format(spec)
        )
    if not _NAME_RE.match(group):
        raise AnsibleFilterError(
            "sysusers group {!r} is not a valid group name".format(group)
        )
    return "m {} {}".format(name, group)


def sysusers_render(specs):
    """Render SYSUSERS specs into sysusers.d(5) fragment lines.

    Args:
        specs: string / mapping list (see module docstring for forms).

    Returns:
        Fragment body (str), newline-terminated; empty string for no specs.

    Raises:
        AnsibleFilterError: on invalid names, kinds, or missing fields.
    """
    declared = {}  # name -> line, for u/g same-name override (later wins)
    declare_order = []  # g names then u names, first-seen order
    members = []

    for raw in _arrayitize(specs):
        if isinstance(raw, string_types):
            raw = {"name": raw}
        if not isinstance(raw, dict):
            raise AnsibleFilterError(
                "sysusers spec must be a string or mapping, got {!r}".format(raw)
            )
        kind = raw.get("kind", "member" if raw.get("member") is not None else "user")
        if kind not in _KINDS:
            raise AnsibleFilterError(
                "sysusers spec {!r}: kind must be one of {}, got {!r}".format(
                    raw, "/".join(_KINDS), kind
                )
            )
        if kind == "member":
            members.append(_member_line(raw))
            continue
        line = _group_line(raw) if kind == "group" else _user_line(raw)
        name = raw["name"]
        if name not in declared:
            declare_order.append((kind, name))
        # Same name re-declared: later spec wins outright (authored overrides
        # derived -- gen_sysusers.tasks prepends derived entries).
        declared[name] = line

    lines = []
    for want_kind in ("group", "user"):
        for kind, name in declare_order:
            if kind == want_kind:
                lines.append(declared[name])
    seen = set()
    for line in members:
        if line not in seen:
            seen.add(line)
            lines.append(line)
    return "\n".join(lines) + "\n" if lines else ""


class FilterModule(object):
    def filters(self):
        return {"sysusers_render": sysusers_render}
