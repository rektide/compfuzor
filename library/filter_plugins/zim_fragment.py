from __future__ import annotations

import collections.abc

from ansible.errors import AnsibleFilterError
from ansible.module_utils.six import string_types
from ansible.plugins.test.core import wrapped_test_undefined
from ansible.template import accept_args_markers


# Canonical Zim phase -> sort number on a 00-99 scale.
# Gaps leave headroom for contributors to place modules between bands or
# before core / after late by passing a numeric phase directly.
PHASE_NUMBERS = {
    "core": 20,
    "prompt": 40,
    "tools": 55,
    "completion": 70,
    "late": 85,
}


def _is_sequence(value):
    return isinstance(value, collections.abc.Sequence) and not isinstance(
        value, string_types
    )


def _resolve_phase(phase, default):
    """Resolve a phase spec to an int in 0-99.

    ``phase`` may be a number (used directly) or a predefined phase name.
    Falls back to ``default`` when unset. Returns None only when both the
    entry phase and the default are absent.
    """
    value = phase
    if value is None or wrapped_test_undefined(value):
        value = default
    if value is None or wrapped_test_undefined(value):
        return None
    # bool is an int subclass; reject it so True/False are not silently 1/0.
    if isinstance(value, bool):
        raise AnsibleFilterError(
            "zim phase must be a number or phase name, got bool"
        )
    if isinstance(value, (int, float)):
        n = int(value)
    else:
        text = str(value).strip().lower()
        if text == "":
            return None
        if text.isdigit():
            n = int(text)
        elif text in PHASE_NUMBERS:
            n = PHASE_NUMBERS[text]
        else:
            raise AnsibleFilterError(
                "zim phase must be a number (00-99) or one of {}, got {!r}".format(
                    sorted(PHASE_NUMBERS), text
                )
            )
    if not 0 <= n <= 99:
        raise AnsibleFilterError(
            "zim phase number must be in 00-99, got {}".format(n)
        )
    return n


def _slug(source):
    """Derive a filename slug from a module source.

    Takes the last path segment of a bare name, owner/repo, or URL, stripping
    a trailing ``.git`` and any query/fragment.
    """
    text = str(source).strip()
    for sep in ("?", "#"):
        if sep in text:
            text = text.split(sep, 1)[0]
    text = text.rstrip("/")
    if text.endswith(".git"):
        text = text[: -len(".git")]
    if "/" in text:
        text = text.rsplit("/", 1)[1]
    return text


def _join_args(args):
    if args is None or wrapped_test_undefined(args):
        return ""
    if isinstance(args, string_types):
        return str(args).strip()
    if _is_sequence(args):
        parts = []
        for a in args:
            if a is None or wrapped_test_undefined(a):
                continue
            parts.append(str(a).strip())
        return " ".join(p for p in parts if p)
    raise AnsibleFilterError(
        "zim module args must be a string or list, got {}".format(
            type(args).__name__
        )
    )


def _normalize_entry(entry, default_phase):
    if isinstance(entry, string_types):
        entry = {"source": entry}
    elif not isinstance(entry, collections.abc.Mapping):
        raise AnsibleFilterError(
            "zim module entries must be strings or mappings, got {}".format(
                type(entry).__name__
            )
        )
    if "source" not in entry:
        raise AnsibleFilterError("zim module entry requires a 'source'")

    source = str(entry["source"]).strip()
    if not source:
        raise AnsibleFilterError("zim module source must be non-empty")

    num = _resolve_phase(entry.get("phase"), default_phase)
    if num is None:
        raise AnsibleFilterError(
            "zim module {!r} has no phase (set 'phase' or a default phase)".format(
                source
            )
        )

    name = str(entry.get("name") or _slug(source)).strip()
    if not name:
        raise AnsibleFilterError(
            "zim module {!r} resolves to an empty filename slug".format(source)
        )

    description = entry.get("description")
    if description is not None and not wrapped_test_undefined(description):
        description = str(description).strip() or None
    else:
        description = None

    enabled = entry.get("enabled", True)
    if enabled is None or wrapped_test_undefined(enabled):
        enabled = True
    enabled = bool(enabled)

    return {
        "source": source,
        "num": num,
        "name": name,
        "description": description,
        "args": entry.get("args"),
        "comment": entry.get("comment"),
        "enabled": enabled,
    }


def _filename(num, name, description):
    fn = "{:02d}-{}".format(num, name)
    if description:
        fn += "-{}".format(description)
    return fn + ".conf"


def _body(source, args, comment):
    lines = []
    if comment is not None and not wrapped_test_undefined(comment):
        comments = comment if _is_sequence(comment) else [comment]
        for c in comments:
            for cl in str(c).splitlines():
                lines.append("# " + cl if cl else "#")
    arg_str = _join_args(args)
    if arg_str:
        lines.append("zmodule {} {}".format(source, arg_str))
    else:
        lines.append("zmodule {}".format(source))
    return "\n".join(lines) + "\n"


@accept_args_markers
def zim_fragment(modules, phase=None):
    """Render zim module declarations into drop-in fragment files.

    Each entry becomes one fragment file under ``etc/zim/`` (or
    ``etc/zim-disabled/`` when ``enabled: false``). Filenames are
    ``<num>-<name>[-<description>].conf`` where ``<num>`` is the resolved
    phase number, so lexical sort across contributors yields deterministic
    load order. The existing block-in-file config assembler globs these in
    sorted order to build the final zimfw config.

    ``modules`` may be a single string/mapping or a list of them. ``phase``
    is a default phase (number or name) applied to entries without one.

    Returns a list of ``{name, content}`` records shaped as ETC_FILES entries.
    """
    if modules is None or wrapped_test_undefined(modules):
        return []

    if isinstance(modules, (string_types, collections.abc.Mapping)):
        items = [modules]
    elif _is_sequence(modules):
        items = [m for m in modules if m is not None and not wrapped_test_undefined(m)]
    else:
        raise AnsibleFilterError(
            "zim_fragment expects a string, mapping, or list, got {}".format(
                type(modules).__name__
            )
        )

    results = []
    for entry in items:
        norm = _normalize_entry(entry, phase)
        fn = _filename(norm["num"], norm["name"], norm["description"])
        rel_dir = "etc/zim-disabled/" if not norm["enabled"] else "etc/zim/"
        results.append(
            {
                "name": rel_dir + fn,
                "content": _body(norm["source"], norm["args"], norm["comment"]),
            }
        )
    return results


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"zim_fragment": zim_fragment}
