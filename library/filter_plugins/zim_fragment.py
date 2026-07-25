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

    has_env = "env" in entry and not wrapped_test_undefined(entry["env"])
    has_source = "source" in entry
    if has_env and has_source:
        raise AnsibleFilterError(
            "zim module entry cannot have both 'env' and 'source'"
        )
    if not has_env and not has_source:
        raise AnsibleFilterError("zim module entry requires 'source' or 'env'")

    # kind: env (generated env-setting script) | file (local .zsh) | git (cloned)
    env_map = None
    source = ""
    if has_env:
        env_map = entry["env"]
        if not isinstance(env_map, collections.abc.Mapping):
            raise AnsibleFilterError(
                "zim module 'env' must be a mapping of VAR -> value"
            )
        if not env_map:
            raise AnsibleFilterError("zim module 'env' mapping is empty")
        kind = "env"
    else:
        source = str(entry["source"]).strip()
        if not source:
            raise AnsibleFilterError("zim module source must be non-empty")
        # A local-file module: source is a repo .zsh rendered as a local zimfw
        # module (zmodule <abspath>). Triggered by a .zsh extension or file: true.
        kind = "file" if (bool(entry.get("file")) or source.endswith(".zsh")) else "git"

    num = _resolve_phase(entry.get("phase"), default_phase)
    if num is None:
        raise AnsibleFilterError(
            "zim module {!r} has no phase (set 'phase' or a default phase)".format(
                source or kind
            )
        )

    name = str(entry.get("name") or "").strip()
    if not name and kind in ("git", "file"):
        slug = _slug(source)
        if kind == "file" and slug.endswith(".zsh"):
            slug = slug[: -len(".zsh")]
        name = slug
    if not name:
        raise AnsibleFilterError(
            "zim module requires 'name' (env modules have no source to derive one)"
            if kind == "env"
            else "zim module {!r} resolves to an empty filename slug".format(source)
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
        "kind": kind,
        "source": source,
        "env": env_map,
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


def _comment_lines(comment):
    out = []
    if comment is not None and not wrapped_test_undefined(comment):
        comments = comment if _is_sequence(comment) else [comment]
        for c in comments:
            for cl in str(c).splitlines():
                out.append("# " + cl if cl else "#")
    return out


def _body(source, args, comment):
    lines = _comment_lines(comment)
    arg_str = _join_args(args)
    if arg_str:
        lines.append("zmodule {} {}".format(source, arg_str))
    else:
        lines.append("zmodule {}".format(source))
    return "\n".join(lines) + "\n"


def _env_body(env_map, comment):
    """Render an env module's init.zsh: one don't-stomp guard per var.

    Honors the gen_bins COMPFUZOR_ENV_OVERWRITE convention -- existing values
    win unless the operator opts into the generated ones.
    """
    lines = _comment_lines(comment)
    lines.append("# Auto-generated by compfuzor zim (env module).")
    lines.append("# Exports vars without stomping existing values;")
    lines.append("# set COMPFUZOR_ENV_OVERWRITE=1 to force the generated values.")
    for key, value in env_map.items():
        lines.append(
            'if [ -z "${{{0}:-}}" ] || [ -n "${{COMPFUZOR_ENV_OVERWRITE:-}}" ]; then'.format(
                key
            )
        )
        lines.append('  export {0}="{1}"'.format(key, value))
        lines.append("fi")
    return "\n".join(lines) + "\n"


@accept_args_markers
def zim_fragment(modules, phase=None, etc=None):
    """Render zim module declarations into drop-in fragment files.

    Each entry becomes one fragment file under ``zim/`` (or ``zim-disabled/``
    when ``enabled: false``). Filenames are ``<num>-<name>[-<description>].conf``
    where ``<num>`` is the resolved phase number, so lexical sort across
    contributors yields deterministic load order. The block-in-file config
    assembler globs these in sorted order to build the final zimfw config.

    ``modules`` may be a single string/mapping or a list of them. ``phase``
    is a default phase (number or name) applied to entries without one.

    ``etc`` is the contributor's ETC dir. When set, a local module is rendered
    as a zimfw module loaded by absolute path: the declaration points at
    ``<etc>/zim-modules/<name>`` (zimfw loads abspaths as already-installed
    modules) and a ``zim-modules/<name>/init.zsh`` record is emitted. Two local
    kinds: a **file** module (source ending in ``.zsh`` or ``file: true``) --
    init.zsh carries ``src`` resolved from files/<TYPE>/; and an **env** module
    (``env`` mapping of VAR -> value) -- init.zsh carries generated ``content``
    with one don't-stomp-per-var guard (COMPFUZOR_ENV_OVERWRITE forces).

    Returns a list of ``{name, content}`` records shaped as ETC_FILES entries
    (file modules additionally emit a ``{name, src}`` init.zsh record).

    ``name`` is relative to the ETC dir (the ETC_FILES writer base), so it is
    ``zim/<file>`` / ``zim-disabled/<file>`` -- NOT ``etc/zim/...``. The latter
    would double up to ``ETC/etc/zim`` and miss ``install-zim.sh``'s
    ``DIR/etc/zim`` glob (DIR/etc is a symlink to ETC).
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
        rel_dir = "zim-disabled/" if not norm["enabled"] else "zim/"
        if norm["kind"] in ("env", "file"):
            # local zimfw module: zmodule points at the rendered module dir.
            module_path = (
                "{}/zim-modules/{}".format(etc, norm["name"]) if etc else norm["name"]
            )
            results.append(
                {
                    "name": rel_dir + fn,
                    "content": _body(module_path, norm["args"], norm["comment"]),
                }
            )
            # render the module script; only active modules need one on disk.
            # env -> generated content; file -> src resolved from files/<TYPE>/.
            if norm["enabled"]:
                module_file = {
                    "name": "zim-modules/{}/init.zsh".format(norm["name"]),
                }
                if norm["kind"] == "env":
                    module_file["content"] = _env_body(norm["env"], norm["comment"])
                else:
                    module_file["src"] = norm["source"]
                results.append(module_file)
        else:
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
