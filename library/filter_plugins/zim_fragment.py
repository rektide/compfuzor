from __future__ import annotations

import collections.abc
import re

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
ZSH_PARAMETER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ZIM_CHANNELS = {"zimenv", "zimrc"}
# Jinja markers that must never survive into an emitted zsh body: any
# occurrence means a declaration value reached this filter unrendered and
# would install literally (``{{var}}`` text inside init.zsh). Callers own
# rendering -- gen_zim.tasks renders declaration values at the synthesis
# task via the template_value lookup.
TEMPLATE_MARKERS = ("{{",)
# A bare ``{%`` is legal Zsh (date prompt escapes such as ``%D{%Y}``), so
# only a complete Jinja block (``{% ... %}`` / ``{%- ... -%}``) is rejected.
TEMPLATE_BLOCK = re.compile(r"\{%-?[\s\S]*?-?%\}")


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


def _reject_template_markers(module, field, value):
    """Refuse declaration values still carrying Jinja template syntax.

    Every value flowing into an emitted fragment or init.zsh body must be
    fully rendered before this filter: ansible never re-templates filter
    output, so surviving markers install as literal text. ``{{`` is
    rejected outright; ``{%`` only as a complete Jinja block, because Zsh
    date prompts like ``%D{%Y}`` legitimately carry a bare ``{%``. The
    error names the module and the offending field so the broken
    declaration can be located directly.
    """
    values = value if _is_sequence(value) else [value]
    for item in values:
        if item is None or wrapped_test_undefined(item):
            continue
        text = str(item)
        marker = next((m for m in TEMPLATE_MARKERS if m in text), None)
        if marker is None:
            block = TEMPLATE_BLOCK.search(text)
            marker = block.group(0) if block is not None else None
        if marker is not None:
            shown = text if len(text) <= 120 else text[:117] + "..."
            raise AnsibleFilterError(
                "zim module {!r}: {} still contains template marker {!r}; "
                "declaration values must be rendered before zim_fragment "
                "(gen_zim.tasks renders them at the synthesis task via "
                "the template_value lookup); "
                "unresolved value: {!r}".format(
                    module, field, marker, shown
                )
            )


def _reject_declaration_markers(norm):
    """Check every declaration field that flows into an emitted body."""
    name = norm["name"]
    if norm["source"]:
        _reject_template_markers(name, "source", norm["source"])
    _reject_template_markers(name, "args", norm["args"])
    _reject_template_markers(name, "comment", norm["comment"])
    for comp in norm["completions"]:
        _reject_template_markers(name, "completions entry", comp)
    if norm["env"]:
        for key, value in norm["env"].items():
            _reject_template_markers(name, "env[{!r}]".format(key), value)
    if norm["arrays"]:
        for param, values in norm["arrays"].items():
            for index, value in enumerate(values):
                _reject_template_markers(
                    name, "arrays[{!r}][{}]".format(param, index), value
                )
    if norm["aliases"]:
        for alias, expansion in norm["aliases"].items():
            _reject_template_markers(name, "aliases[{!r}]".format(alias), expansion)
    if norm["functions"]:
        for fname, body in norm["functions"].items():
            _reject_template_markers(name, "functions[{!r}]".format(fname), body)


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
    has_arrays = "arrays" in entry and not wrapped_test_undefined(
        entry["arrays"]
    )
    has_aliases = "aliases" in entry and not wrapped_test_undefined(entry["aliases"])
    has_functions = "functions" in entry and not wrapped_test_undefined(entry["functions"])
    has_completions = "completions" in entry and not wrapped_test_undefined(
        entry["completions"]
    )
    body_kinds = sum(
        1
        for flag in (has_env, has_arrays, has_source, has_aliases, has_functions)
        if flag
    )
    if body_kinds > 1:
        raise AnsibleFilterError(
            "zim module entry can have only one of 'env', 'arrays', 'source', 'aliases', 'functions'"
        )
    if body_kinds == 0 and not has_completions:
        raise AnsibleFilterError(
            "zim module entry requires one of 'source', 'env', 'arrays', 'aliases', "
            "'functions', or 'completions'"
        )
    if not has_completions:
        pass
    elif isinstance(entry["completions"], str) or not isinstance(
        entry["completions"], collections.abc.Sequence
    ):
        raise AnsibleFilterError(
            "zim module 'completions' must be a list of completion filenames"
        )
    elif not list(entry["completions"]):
        raise AnsibleFilterError("zim module 'completions' list is empty")
    elif any(
        not isinstance(c, str) or not c.strip() or "/" in c
        for c in entry["completions"]
    ):
        raise AnsibleFilterError(
            "zim module 'completions' entries must be plain filenames (no '/')"
        )

    # kind: env/aliases/functions (generated init.zsh) | file (local .zsh) |
    # git (cloned). 'completions' may ride along with any local kind (adds an
    # fpath dir); alone it is a pure-completion module.
    env_map = None
    array_map = None
    alias_map = None
    func_map = None
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
    elif has_arrays:
        array_map = entry["arrays"]
        if not isinstance(array_map, collections.abc.Mapping):
            raise AnsibleFilterError(
                "zim module 'arrays' must be a mapping of parameter -> list"
            )
        if not array_map:
            raise AnsibleFilterError("zim module 'arrays' mapping is empty")
        for name, values in array_map.items():
            if not isinstance(name, string_types) or not ZSH_PARAMETER.match(name):
                raise AnsibleFilterError(
                    "zim module array parameter names must be valid Zsh identifiers"
                )
            if not _is_sequence(values):
                raise AnsibleFilterError(
                    "zim module array {!r} must be a list".format(name)
                )
            if any(
                isinstance(value, (collections.abc.Mapping, list, tuple))
                for value in values
            ):
                raise AnsibleFilterError(
                    "zim module array {!r} values must be scalars".format(name)
                )
        kind = "arrays"
    elif has_aliases:
        alias_map = entry["aliases"]
        if not isinstance(alias_map, collections.abc.Mapping):
            raise AnsibleFilterError(
                "zim module 'aliases' must be a mapping of alias -> expansion"
            )
        if not alias_map:
            raise AnsibleFilterError("zim module 'aliases' mapping is empty")
        kind = "aliases"
    elif has_functions:
        func_map = entry["functions"]
        if not isinstance(func_map, collections.abc.Mapping):
            raise AnsibleFilterError(
                "zim module 'functions' must be a mapping of name -> body"
            )
        if not func_map:
            raise AnsibleFilterError("zim module 'functions' mapping is empty")
        kind = "functions"
    elif has_source:
        source = str(entry["source"]).strip()
        if not source:
            raise AnsibleFilterError("zim module source must be non-empty")
        # A local-file module: source is a repo .zsh rendered as a local zimfw
        # module (zmodule <abspath>). Triggered by a .zsh extension or file: true.
        kind = "file" if (bool(entry.get("file")) or source.endswith(".zsh")) else "git"
    else:
        kind = "completions"

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
        if kind in ("env", "arrays", "aliases", "functions", "completions"):
            raise AnsibleFilterError(
                "zim module requires 'name' ({} modules have no source to derive one)".format(
                    kind
                )
            )
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

    channel = entry.get("channel", "zimrc")
    if channel is None or wrapped_test_undefined(channel):
        channel = "zimrc"
    channel = str(channel).strip()
    if channel not in ZIM_CHANNELS:
        raise AnsibleFilterError(
            "zim module channel must be one of {}, got {!r}".format(
                sorted(ZIM_CHANNELS), channel
            )
        )

    return {
        "kind": kind,
        "source": source,
        "env": env_map,
        "arrays": array_map,
        "aliases": alias_map,
        "functions": func_map,
        "completions": list(entry["completions"]) if has_completions else [],
        "num": num,
        "name": name,
        "description": description,
        "args": entry.get("args"),
        "comment": entry.get("comment"),
        "enabled": enabled,
        "channel": channel,
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
    """Render an env module's init.zsh with centralized don't-stomp policy.

    Honors the gen_bins COMPFUZOR_ENV_OVERWRITE convention -- existing values
    win unless the operator opts into overwriting. The spec accepts:
      * all-tokens (case-insensitive): 1, true, y, yes, *  -> every var
      * otherwise: a comma-separated list of glob patterns matched against the
        variable name (also case-insensitive), e.g. WATCHMAN_*,SSH_AUTH_SOCK
    """
    lines = _comment_lines(comment)
    lines.append("# Auto-generated by compfuzor zim (env module). Exports vars")
    lines.append("# without stomping existing values. Force via")
    lines.append("# COMPFUZOR_ENV_OVERWRITE: 1/true/y/yes/* = all vars; otherwise")
    lines.append("# a comma-separated list of glob patterns on the variable name.")
    lines.append("_compfuzor_env_overwrite() {")
    lines.append('  local spec="${(U)COMPFUZOR_ENV_OVERWRITE:-}"')
    lines.append('  [ -z "$spec" ] && return 1')
    lines.append("  case \"$spec\" in 1|TRUE|YES|Y|'*') return 0 ;; esac")
    lines.append("  local p")
    lines.append('  for p in ${(s:,:)spec}; do')
    lines.append('    case "${(U)1}" in $~p) return 0 ;; esac')
    lines.append("  done")
    lines.append("  return 1")
    lines.append("}")
    lines.append("_compfuzor_env_set() {")
    lines.append('  local name="$1" value="$2"')
    lines.append('  [ -n "${(P)name:-}" ] && ! _compfuzor_env_overwrite "$name" && return 0')
    lines.append('  export "$name=$value"')
    lines.append("}")
    for key, value in env_map.items():
        lines.append('_compfuzor_env_set {0} "{1}"'.format(key, value))
    return "\n".join(lines) + "\n"


def _array_body(array_map, comment):
    """Render Zsh arrays with explicit array references and don't-stomp policy."""
    lines = _comment_lines(comment)
    lines.append("# Auto-generated by compfuzor zim (array module).")
    lines.append("# Existing non-empty arrays win unless COMPFUZOR_ENV_OVERWRITE matches.")
    lines.append("_compfuzor_env_overwrite() {")
    lines.append('  local spec="${(U)COMPFUZOR_ENV_OVERWRITE:-}"')
    lines.append('  [ -z "$spec" ] && return 1')
    lines.append("  case \"$spec\" in 1|TRUE|YES|Y|'*') return 0 ;; esac")
    lines.append("  local p")
    lines.append('  for p in ${(s:,:)spec}; do')
    lines.append('    case "${(U)1}" in $~p) return 0 ;; esac')
    lines.append("  done")
    lines.append("  return 1")
    lines.append("}")
    lines.append("_compfuzor_array_set() {")
    lines.append('  local name="$1" values_name="$2"')
    lines.append(
        '  (( ${(P)#name} )) && ! _compfuzor_env_overwrite "$name" && return 0'
    )
    lines.append(
        '  (( ${(P)#values_name} )) && set -A "$name" "${(@P)values_name}" && return 0'
    )
    lines.append('  set -A "$name"')
    lines.append("}")
    for index, (name, values) in enumerate(array_map.items()):
        temp = "_compfuzor_array_values_{}".format(index)
        rendered = " ".join('"{}"'.format(value) for value in values)
        lines.append("typeset -a {}=({})".format(temp, rendered))
        lines.append("_compfuzor_array_set {} {}".format(name, temp))
        lines.append("unset {}".format(temp))
    return "\n".join(lines) + "\n"


def _alias_body(alias_map, comment):
    """Render an aliases module's init.zsh: one `alias` line per entry."""
    lines = _comment_lines(comment)
    lines.append("# Auto-generated by compfuzor zim (aliases module).")
    for alias, expansion in alias_map.items():
        quoted = str(expansion).replace("'", "'\\''")
        lines.append("alias {}='{}'".format(alias, quoted))
    return "\n".join(lines) + "\n"


def _functions_body(func_map, comment):
    """Render a functions module's init.zsh: one function definition per entry."""
    lines = _comment_lines(comment)
    lines.append("# Auto-generated by compfuzor zim (functions module).")
    for fname, body in func_map.items():
        lines.append("{}() {{".format(fname))
        for bl in str(body).splitlines():
            lines.append("  " + bl if bl.strip() else bl)
        lines.append("}")
    return "\n".join(lines) + "\n"


def _fpath_line():
    """fpath entry for a module's bundled completions (relative to init.zsh)."""
    return "fpath=(${0:h}/functions $fpath)"


@accept_args_markers
def zim_fragment(modules, phase=None, etc=None, host=False):
    """Render zim module declarations into drop-in fragment files.

    Each contributor entry becomes one fragment file under
    ``zim/<channel>/active/`` (or ``zim/<channel>/disabled/`` when
    ``enabled: false``). With ``host: true``, the same renderer instead emits
    directly into ``<channel>.d/`` and appends the compiled config's disabled
    suffix for disabled entries. The channel defaults to ``zimrc``. Filenames are
    ``<num>-<name>[-<description>].conf`` where ``<num>`` is the resolved phase
    number, so lexical sort across contributors yields deterministic load
    order. The block-in-file config assembler globs these in sorted order to
    build each channel's final zimfw config.

    ``modules`` may be a single string/mapping or a list of them. ``phase``
    is a default phase (number or name) applied to entries without one.

    ``etc`` is the contributor's ETC dir. When set, a local module is rendered
    as a zimfw module loaded by absolute path: the declaration points at
    ``<etc>/zim-modules/<name>`` (zimfw loads abspaths as already-installed
    modules) and a ``zim-modules/<name>/init.zsh`` record is emitted. Two local
    kinds: a **file** module (source ending in ``.zsh`` or ``file: true``) --
    init.zsh carries ``src`` resolved from files/<TYPE>/; and an **env** module
    (``env`` mapping of VAR -> value) -- init.zsh carries generated ``content``
    with one don't-stomp-per-var guard (COMPFUZOR_ENV_OVERWRITE forces); and
    an **arrays** module (mapping of Zsh parameter -> explicit list), including
    tied arrays such as ``path``.
    Additional generated kinds: **aliases** (mapping alias -> expansion, one
    ``alias`` line each), **functions** (mapping name -> body, one definition
    each), and **completions** (list of completion filenames, resolved from
    files/<TYPE>/ into ``zim-modules/<name>/functions/`` with an fpath entry;
    may ride along with any local kind, or stand alone as a pure-completion
    module). A file module with completions gets a generated init.zsh that
    fpath-prepends and sources the original as ``body.zsh``.

    Returns a list of ``{name, content}`` records shaped as ETC_FILES entries
    (file modules additionally emit a ``{name, src}`` init.zsh record).

    Declaration values must already be fully rendered when they arrive:
    any ``{{`` marker or complete ``{% ... %}`` Jinja block surviving in a
    declaration field (env/arrays/aliases/functions values, source, args,
    comment, completions) or in a composed body raises an error naming the
    module and field -- unrendered markers would otherwise install
    literally, since nothing re-templates filter output downstream. A
    bare ``{%`` is legitimate Zsh (date prompt escapes like ``%D{%Y}``)
    and passes. Callers render nested values first (``gen_zim.tasks``
    applies the ``template_value`` lookup at the synthesis task).

    ``name`` is relative to the ETC dir (the ETC_FILES writer base), so it is
    ``zim/<channel>/<state>/<file>`` -- NOT ``etc/zim/...``. The latter would
    double up to ``ETC/etc/zim`` and miss ``install-zim.sh``'s ``DIR/etc/zim``
    glob (DIR/etc is a symlink to ETC).
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
    seen_fragments = {}
    host = bool(host) and not wrapped_test_undefined(host)
    for entry in items:
        norm = _normalize_entry(entry, phase)
        # Loud guard for the nested-value rendering trap: refuse any
        # declaration value (or composed body below) that still carries
        # template markers rather than shipping them literally.
        _reject_declaration_markers(norm)
        fn = _filename(norm["num"], norm["name"], norm["description"])
        state = "active" if norm["enabled"] else "disabled"
        fragment_key = (norm["channel"], fn)
        if fragment_key in seen_fragments:
            raise AnsibleFilterError(
                "zim module declarations conflict for {}/{} ({} and {})".format(
                    norm["channel"], fn, seen_fragments[fragment_key], state
                )
            )
        seen_fragments[fragment_key] = state
        if host:
            fragment_name = "{}.d/{}{}".format(
                norm["channel"], fn, "" if norm["enabled"] else ".disabled"
            )
        else:
            fragment_name = "zim/{}/{}/{}".format(norm["channel"], state, fn)
        local_kinds = (
            "env",
            "arrays",
            "aliases",
            "functions",
            "completions",
            "file",
        )
        if norm["kind"] in local_kinds:
            # local zimfw module: zmodule points at the rendered module dir.
            module_path = (
                "{}/zim-modules/{}".format(etc, norm["name"]) if etc else norm["name"]
            )
            fragment_content = _body(module_path, norm["args"], norm["comment"])
            _reject_template_markers(
                norm["name"],
                "emitted fragment body {!r}".format(fragment_name),
                fragment_content,
            )
            results.append(
                {
                    "name": fragment_name,
                    "content": fragment_content,
                }
            )
            # render the module script; only active modules need one on disk.
            # generated kinds -> content; file -> src resolved from files/<TYPE>/
            # (wrapped in a sourcing init.zsh when completions ride along).
            # completions -> per-file src records under functions/ + an fpath
            # entry in init.zsh.
            if norm["enabled"]:
                completions = norm["completions"]
                if norm["kind"] == "env":
                    init_lines = [_env_body(norm["env"], norm["comment"]).rstrip("\n")]
                elif norm["kind"] == "arrays":
                    init_lines = [
                        _array_body(norm["arrays"], norm["comment"]).rstrip("\n")
                    ]
                elif norm["kind"] == "aliases":
                    init_lines = [
                        _alias_body(norm["aliases"], norm["comment"]).rstrip("\n")
                    ]
                elif norm["kind"] == "functions":
                    init_lines = [
                        _functions_body(norm["functions"], norm["comment"]).rstrip("\n")
                    ]
                elif completions:
                    init_lines = []
                else:
                    init_lines = None
                if init_lines is None:
                    # file kind, no completions: init.zsh IS the source file
                    results.append(
                        {
                            "name": "zim-modules/{}/init.zsh".format(norm["name"]),
                            "src": norm["source"],
                        }
                    )
                else:
                    if completions:
                        init_lines.insert(0, _fpath_line())
                    if norm["kind"] == "file":
                        init_lines.append("source ${0:h}/body.zsh")
                    init_content = "\n".join(init_lines) + "\n"
                    _reject_template_markers(
                        norm["name"],
                        "emitted init.zsh body",
                        init_content,
                    )
                    results.append(
                        {
                            "name": "zim-modules/{}/init.zsh".format(norm["name"]),
                            "content": init_content,
                        }
                    )
                    if norm["kind"] == "file":
                        results.append(
                            {
                                "name": "zim-modules/{}/body.zsh".format(norm["name"]),
                                "src": norm["source"],
                            }
                        )
                    for comp in completions:
                        results.append(
                            {
                                "name": "zim-modules/{}/functions/{}".format(
                                    norm["name"], comp
                                ),
                                "src": comp,
                            }
                        )
        else:
            fragment_content = _body(norm["source"], norm["args"], norm["comment"])
            _reject_template_markers(
                norm["name"],
                "emitted fragment body {!r}".format(fragment_name),
                fragment_content,
            )
            results.append(
                {
                    "name": fragment_name,
                    "content": fragment_content,
                }
            )
    return results


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"zim_fragment": zim_fragment}
