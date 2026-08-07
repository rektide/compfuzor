# Ansible Plugin Reference

`/library` contains custom Ansible plugins used by Compfuzor: **filters**
(`library/filter_plugins/`, used with `|` in Jinja) and **tests**
(`library/test_plugins/`, used with `is` in conditionals).

Each `.py` file defines a `FilterModule` or `TestModule` class whose
`filters()`/`tests()` method returns a dict mapping the **registered name**
(the name used in Jinja, e.g. `{{ x | normalize(to='list') }}`) to a Python
callable. The registered name sometimes differs from the filename. Source
references are bundle-root-relative.

> **Convention key** — *Undefined/None handling*:
> - **tolerates undefined → X**: the function explicitly checks for
>   `AnsibleUndefined` (via `wrapped_test_undefined`) or `None` (via `_is_nothing`)
>   and returns `X` instead of raising.
> - **raises on undefined**: no such guard; a bare undefined reference either
>   raises at the Jinja call site (strict mode) or leaks through as an
>   `AnsibleUndefined` object. Not safe for missing inputs.

---

## Tests

Tests are used with `is` in Jinja/Ansible conditionals.

| Test | Signature | Purpose | Source |
|---|---|---|---|
| `deftruthy` | `(default?, use_default_on_falsy=False)` | True if resolved value is truthy; undefined → `False` (or `default`). | [`deftruthy.py`](/library/test_plugins/deftruthy.py) |
| `deffalsy` | `(default?, use_default_on_falsy=False)` | True if resolved value is falsy; undefined → `True` (or `not default`). | [`deftruthy.py`](/library/test_plugins/deftruthy.py) |
| `having` / `havingattr` | `(*attrs)` | True if dict has all requested attributes with truthy values. | [`havingattr.py`](/library/test_plugins/havingattr.py) |
| `havingany` | `(*attrs)` | True if dict has any requested attribute with a truthy value. | [`havingattr.py`](/library/test_plugins/havingattr.py) |
| `defmapping` | | True if value is a mapping (dict). | [`defmapping.py`](/library/test_plugins/defmapping.py) |
| `deflengthy` | | True if value is list-like with `len > 0`. | [`deflengthy.py`](/library/test_plugins/deflengthy.py) |

**Examples**

```yaml
when: MY_FLAG is deftruthy
when: MY_BYPASS is deffalsy
when: my_dict is having('foo', 'bar')
when: KERNEL_MODULES is defmapping
```

---

## Shape conversion & rendering

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `normalize` | `(value, *, to='list', **options)` | Convert one raw value to a registered shape: `list` (scalar → `[x]`, undefined/False → `[]`), `mapping` (with optional `shorthand=True`), `items` (dict → `[{key_name, value_name}]`), or `identity`. | **tolerates undefined → `[]`** (list), `{}` (mapping), `[]` (items). `False` → empty. `True` is kept as `[True]`. | [`cfmerge.py`](/library/filter_plugins/cfmerge.py) |
| `join2` | `(value, separator='')` | Coerce to list and join into a string, dropping boolean sentinels. Composes `normalize(to='list')` + join — no `default([])` needed, bare strings not character-iterated. | **tolerates undefined → `''`**. `True`/`False` dropped. | [`cfmerge.py`](/library/filter_plugins/cfmerge.py) |
| `rejectAny` | `(list, excluded)` | Filter `list`, dropping elements present in `excluded`. | Raises on undefined — no guards. | [`rejectAny.py`](/library/filter_plugins/rejectAny.py) |

**Examples**

```jinja
{{ FOO | normalize(to='list') }}              {# undefined -> [], "x" -> ["x"], [1,2] -> [1,2] #}
{{ STATUS_DIRS | join2(':') }}                {# undefined -> "", ["a","b"] -> "a:b", True -> "" #}
{{ LINKS | normalize(to='items', key_name='dest', value_name='src') }}
{{ [1,2,3,4] | rejectAny([2,4]) }}            {# -> [1,3] #}
```

---

## Merging

The merge family lives in [`cfmerge.py`](/library/filter_plugins/cfmerge.py) — a
fixed pipeline (collect → normalize → combine → refine → extract) selected by
preset name. Each positional arg is one layer; `preset=` is always keyword-only.

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `merge_list` | `(*layers, preset='append', skip_layers=..., get=None, resolve=False)` | Merge variadic list layers through a preset (`append`, `bins_generated`, etc.). `skip_layers=['all']` suppresses all four predicates. | **tolerates undefined/None** — skipped by default (`skip_layers=('none','undefined')`). | [`cfmerge.py`](/library/filter_plugins/cfmerge.py) |
| `merge_dict` | `(*layers, preset='overlay', skip_layers=..., get=None)` | Merge variadic mapping layers through a preset (`overlay`, `tool_versions_overlay`). Later layers win. | **tolerates undefined/None** — same skip behavior. | [`cfmerge.py`](/library/filter_plugins/cfmerge.py) |
| `merge_fields` | `(records, *, profile, get=None)` | Merge records using a recursively nested field profile. | **tolerates undefined/None** — absent records skipped. | [`cfmerge.py`](/library/filter_plugins/cfmerge.py) |
| `combine_iff` | `(base, *overlays)` | Like Ansible's `combine` but silently skips undefined values. Eliminates `({'k': v} if v is defined else {}) | combine(...)` boilerplate. | **tolerates undefined** — undefined overlays and values skipped. | [`cfmerge.py`](/library/filter_plugins/cfmerge.py) |
| `annotate_bins` | `(records, origin_subsystem, bypass_scope=None, subsystem=None)` | Add mergeable disarm provenance/scope metadata to manual BINS aggregations. | **tolerates undefined/None** — returns `[]`. | [`bin_disarm.py`](/library/filter_plugins/bin_disarm.py) |
| `resolve_bin_disarm` | `(name, origin_subsystems=None, bypass_scopes=None, bypass=None, fallback_type=None)` | Resolve canonical action, effective guards, derived verb, and report labels. | Optional metadata may be undefined/None; unusable shapes raise. | [`bin_disarm.py`](/library/filter_plugins/bin_disarm.py) |
| `ignore_empty` | `(obj)` | Strip keys whose value is `None` or `''` from a dict. | Raises on undefined — input must be a defined mapping. | [`ignore_empty.py`](/library/filter_plugins/ignore_empty.py) |

**Examples**

```jinja
{{ BINS | merge_list(_item, preset='bins_generated') }}
{{ ENV | merge_dict(_overlay, preset='overlay') }}
{{ {} | combine_iff({'BIN': RUST_BIN, 'PKG': RUST_PKG}) }}
{{ {"a":1,"b":null,"c":""} | ignore_empty }}   {# -> {"a":1} #}
```

---

## Introspection / Undefined handling

Filters that absorb undefined/missing values so a pipeline doesn't abort.

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `def` | `(*values, falsy=False)` | First argument passing the skip filter, else `None`. `falsy=False` (default) skips only undefined; `falsy=True` also skips Python-falsy values (matches `default(X, true)`); `falsy=[None, '']` skips undefined plus any value in the caller-supplied list. | **tolerates undefined → `None`** when all args are undefined/skipped. | [`def.py:6`](/library/filter_plugins/def.py) |
| `truthy` | `(value, fallback?)` | Coerce to a real boolean; undefined → `False` (or `bool(fallback)`). | **tolerates undefined → `False`**. | [`def.py:16`](/library/filter_plugins/def.py) |
| `deflengthy` | `(value, fallback?)` | True iff value is list-like with `len > 0`; undefined → `False`. | **tolerates undefined → `False`**. | [`def.py:26`](/library/filter_plugins/def.py) |
| `get` | `(value, path, default=None)` | Safe dotted-path traversal through dicts/lists; missing segment, type mismatch, or undefined → `default`. | **tolerates undefined → `default`**. | [`get.py:56`](/library/filter_plugins/get.py) |
| `get_path` | `(value, path, default=None)` | Shared traversal implementation (also exposed directly). | **tolerates undefined → `default`**. | [`get.py:13`](/library/filter_plugins/get.py) |

**Examples**

```jinja
{{ maybe_undef | def([]) }}                  {# -> [] #}
{{ X | def(Y, 'literal fallback') }}         {# first defined of X, Y, or 'literal fallback' #}
{{ X | def(Y, 'default', falsy=True) }}      {# first truthy of X, Y, or 'default' (matches default(X, true)) #}
{{ X | def(Y, falsy=[None, '']) }}           {# first non-None non-empty-string of X or Y #}
{{ maybe_undef | truthy }}                   {# -> false #}
{{ record | get("a.b.c", "fallback") }}
```

---

## Templates / Rendering

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `resolve` | `(value)` *(context-injected)* | Recursively render Jinja template strings inside a value using the current variable scope. Walks dicts/lists/tuples; strings containing `{{` are rendered, everything else passes through. Render errors fall through to the original value. | **tolerates undefined** -- a missing var inside a template string leaves that string unchanged rather than raising. | [`template_render.py:35`](/library/filter_plugins/template_render.py) |

**Examples**

```jinja
# Render template strings inside a YAML-literal dict before it leaves
# task scope (so the stored fact doesn't carry task-local refs):
_inline_etc:
  - name: "foo"
    content: "{{ _local_var }}"
ETC_FILES: "{{ _inline_etc | resolve | merge_list(ETC_FILES, preset='append') }}"

# Same effect via merge_list's resolve= kwarg:
BINS: "{{ BINS | merge_list(_item, preset='bins_generated', resolve=True) }}"
```

Use `resolve` when a value carries template strings referencing variables
(task-local vars, loop vars) that won't be in scope during later rendering
passes — e.g. when a dict literal defined under `vars:` would otherwise be
stored raw in a fact and re-rendered downstream (commonly inside
`fs_hierarchy`) where the task-local vars are gone.

---

## Paths / Strings / Regex

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `deprefix` | `(path, prefixRegex)` | Strip a leading `^prefixRegex` match from `path`; unchanged if no match. | Raises on undefined — no guards; `re.search` on `path`. | [`deprefix.py:3`](/library/filter_plugins/deprefix.py) |
| `depostfix` | `(path, prefixRegex)` | Strip a trailing `prefixRegex$` match. *(Note: keeps `+1` char — likely a bug, see below.)* | Raises on undefined. | [`deprefix.py:10`](/library/filter_plugins/deprefix.py) |
| `deregex` | `(path, regex)` | Return the substring of `path` matching `regex`. | Raises on undefined. | [`deprefix.py:17`](/library/filter_plugins/deprefix.py) |
| `defaultDir` | `(path, defaultDir=False)` | Prefix `path` with `defaultDir/` unless it is already absolute (`/` or `~`). Undefined/`None` path returns `defaultDir` unchanged. | **tolerates undefined path → `defaultDir`**; raises `AnsibleError` (not `raise "str"`) on non-string args or relative path with no base. | [`defaultDir.py:5`](/library/filter_plugins/defaultDir.py) |

> **Heads-up on `depostfix`** ([`deprefix.py:14`](/library/filter_plugins/deprefix.py)): it
> returns `path[:searchLen]` where `searchLen = len(match) + 1`, which **keeps one
> extra character** and drops nothing from the tail. This looks like an off-by-one
> bug compared to `deprefix`; verify before relying on it.---

## Filesystem / Permissions

> **WARNING — whole module is broken for non-local targets.** Filters run on the
> Ansible *controller* host, not the managed target, but call `os.access` /
> `pwd.getpwnam` / `grp.getgrnam`. Results are wrong unless the controller and
> target share users and paths. Prefer `tasks/compfuzor/should_become.tasks`,
> which computes on the target. See the warning at
> [`can_write.py:16`](/library/filter_plugins/can_write.py).

| Filter | Signature | Purpose | Source |
|---|---|---|---|
| `can_write` | `(path, *a, **kw)` | Recursively walk up parents until an existing path is found, then `os.access(path, W_OK)`. | [`can_write.py:70`](/library/filter_plugins/can_write.py) |
| `has_write` | `(path, *a, **kw)` | Plain `os.access(path, W_OK)`. | [`can_write.py:63`](/library/filter_plugins/can_write.py) |
| `should_become` | `(path, user_req?, user_cur?, group_req?, group_cur?)` | True if requested user/group differs from current, or if path isn't writable by current user. | [`can_write.py:84`](/library/filter_plugins/can_write.py) |
| `diff_user` | `(user_req, user_cur, group_req?, group_cur?)` | True if requested vs current uid (and optionally gid) differ. | [`can_write.py:48`](/library/filter_plugins/can_write.py) |
| `to_uid` | `(name_or_uid)` | Resolve a username to its uid (number passes through; unknown → `-1`). | [`can_write.py:28`](/library/filter_plugins/can_write.py) |
| `to_gid` | `(name_or_gid)` | Resolve a group name to its gid. *(Note: line 42 computes `grp.getgrnam(arg).gr_gid` but **never returns it** — always `-1` for names; likely a bug.)* | [`can_write.py:38`](/library/filter_plugins/can_write.py) |

---

## Process / Subsystem generation

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `ansible_cmdline` | `(cmdline)` | Parse `/proc/cmdline`-style string; return `{type, instance}` from the first `<type>.<instance>.pb` token, else `{}`. | **tolerates empty/falsy → `{}`** (`if not cmdline: return {}`); no undefined guard. | [`cmdline.py:4`](/library/filter_plugins/cmdline.py) |
| `tag_each` | `(records, subsystem=None, tag=None, **fields)` | Overlay fields onto every mapping record in a list (e.g. stamp `subsystem='kernel'` onto each BINS entry). | **tolerates undefined → `[]`**; non-mapping items preserved unchanged. | [`each.py`](/library/filter_plugins/each.py) |
| `build_install_bins` | `(stem, basedir=False, src_root="../kernel")` | Emit standard `{build_bins, install_bins}` entries for a stem (e.g. `kernel-sysctl` → `build-kernel-sysctl.sh` / `install-kernel-sysctl.sh`). | Empty/whitespace stem → `{build_bins:[], install_bins:[]}`; no undefined guard. | [`build_install_bins.py:6`](/library/filter_plugins/build_install_bins.py) |
| `bin_composers` | `(bins)` | Group `build*.sh` / `install*.sh` / `apply*.sh` bin entries by action and scope, emitting compositor bins with a `run_all` of children. Honors `scope`, `install-*.user.sh`, `compose: false`. | **tolerates undefined/None/bool → `[]`** (uses a local `_arrayitize` that drops undefined/None/bool). | [`bin_composers.py:34`](/library/filter_plugins/bin_composers.py) |
| `zim_fragment` | `(modules, phase=None, etc=None)` | Render zim module declarations into `zim/<num>-<name>.conf` fragment records (git / file / env kinds). | **tolerates undefined/None `modules` → `[]`** (`wrapped_test_undefined`). | [`zim_fragment.py:251`](/library/filter_plugins/zim_fragment.py) |
| `unsafety` | `(value)` | Tag a value as `TrustedAsTemplate` so Ansible treats it as safe (escapes unsafe-string gating). | No guard; passes value straight to `_tags.TrustedAsTemplate().tag`. | [`unsafety.py:7`](/library/filter_plugins/unsafety.py) |

---

## Debug / Diagnostics

Filters in [`passthrough_inspect.py`](/library/filter_plugins/passthrough_inspect.py).
All `print()` to the controller console and return a value; meant for template
debugging, not production pipelines.

| Filter | Signature | Purpose | Source |
|---|---|---|---|
| `passthrough_inspect` | `(value)` | Print type + contents, return value unchanged. | [`passthrough_inspect.py:5`](/library/filter_plugins/passthrough_inspect.py) |
| `materialize_dict` | `(value)` | Print dict, force `_AnsibleTaggedStr` values to plain `str`, return new dict. | [`passthrough_inspect.py:20`](/library/filter_plugins/passthrough_inspect.py) |
| `count_templates` | `(value)` | Count dict values that are tagged strings still containing `{{`. | [`passthrough_inspect.py:38`](/library/filter_plugins/passthrough_inspect.py) |
| `merge_preserving` | `(value, patch)` | Shallow `dict.update` of `patch` onto `value` with verbose logging; returns `value` if either isn't a dict. | [`passthrough_inspect.py:72`](/library/filter_plugins/passthrough_inspect.py) |

---

## Deprecated

These filters have no live callers and are retained for soak time, but are
inactive. Their sources use the `.py.deprecated` suffix because Ansible's
plugin loader discovers `*.py`; a name such as `merge.deprecated.py` would
still load. Obsolete tests similarly use `.test.py.deprecated`, outside the
normal `tests/filter_plugins/*.test.py` test glob. Use the replacements below.

| Filter | Was | Use instead | Source |
|---|---|---|---|
| `arrayitize` | Coerce to list, dropping `True`/`False`/`None` | `normalize(to='list')` (iteration) or `join2` (text rendering) | [`arrayitize.py.deprecated`](/library/filter_plugins/arrayitize.py.deprecated) |
| `listify` | Coerce to list / dict→items | `normalize(to='list')` or `normalize(to='items')` | [`listify.py.deprecated`](/library/filter_plugins/listify.py.deprecated) |
| `concat` | Variadic list concatenation | `merge_list` | [`listify.py.deprecated`](/library/filter_plugins/listify.py.deprecated) |
| `dictify` | Normalize to mapping | `normalize(to='mapping')` | [`dictify.py.deprecated`](/library/filter_plugins/dictify.py.deprecated) |
| `merge_with_strategy` | Per-field strategy merger | `merge_list`/`merge_dict` with presets | [`merge_strategy.py.deprecated`](/library/filter_plugins/merge_strategy.py.deprecated) |
| `mergeKeyed` | Merge two lists by key | `merge_list` with `merge_keyed` preset | [`mergeKeyed.py.deprecated`](/library/filter_plugins/mergeKeyed.py.deprecated) |
| `merge_list_subsys` / `merge_dict_subsys` / `subsys_publish` | Subsystem-scoped merge/publish | `merge_list`/`merge_dict` (direct calls) | [`merge.py.deprecated`](/library/filter_plugins/merge.py.deprecated) |

---

## Module map

| File | Registered filters | Status |
|---|---|---|
| [`cfmerge.py`](/library/filter_plugins/cfmerge.py) | `normalize`, `merge_list`, `merge_dict`, `merge_fields`, `combine_iff`, `join2` | active |
| [`bin_disarm.py`](/library/filter_plugins/bin_disarm.py) | `annotate_bins`, `canonical_bin_action`, `resolve_bin_disarm` | active |
| [`each.py`](/library/filter_plugins/each.py) | `tag_each` | active |
| [`when.py`](/library/filter_plugins/when.py) | `when`, `whenAnd` | active |
| [`template_render.py`](/library/filter_plugins/template_render.py) | `resolve` | active |
| [`template_data.py`](/library/filter_plugins/template_data.py) | *(internal — raw data-access helpers)* | active |
| [`bin_composers.py`](/library/filter_plugins/bin_composers.py) | `bin_composers` | active |
| [`build_install_bins.py`](/library/filter_plugins/build_install_bins.py) | `build_install_bins` | active |
| [`can_write.py`](/library/filter_plugins/can_write.py) | `can_write`, `has_write`, `should_become`, `diff_user`, `to_uid`, `to_gid` | active |
| [`cmdline.py`](/library/filter_plugins/cmdline.py) | `ansible_cmdline` | active |
| [`def.py`](/library/filter_plugins/def.py) | `def`, `truthy`, `deflengthy` | active |
| [`defaultDir.py`](/library/filter_plugins/defaultDir.py) | `defaultDir` | active |
| [`deprefix.py`](/library/filter_plugins/deprefix.py) | `deprefix`, `depostfix`, `deregex` | active |
| [`get.py`](/library/filter_plugins/get.py) | `get`, `get_path` | active |
| [`ignore_empty.py`](/library/filter_plugins/ignore_empty.py) | `ignore_empty` | active |
| [`passthrough_inspect.py`](/library/filter_plugins/passthrough_inspect.py) | `passthrough_inspect`, `materialize_dict`, `count_templates`, `merge_preserving` | active |
| [`rejectAny.py`](/library/filter_plugins/rejectAny.py) | `rejectAny` | active |
| [`unsafety.py`](/library/filter_plugins/unsafety.py) | `unsafety` | active |
| [`zim_fragment.py`](/library/filter_plugins/zim_fragment.py) | `zim_fragment` | active |
| [`arrayitize.py.deprecated`](/library/filter_plugins/arrayitize.py.deprecated) | `arrayitize` | **deprecated, disabled** |
| [`listify.py.deprecated`](/library/filter_plugins/listify.py.deprecated) | `listify`, `concat` | **deprecated, disabled** |
| [`dictify.py.deprecated`](/library/filter_plugins/dictify.py.deprecated) | `dictify` | **deprecated, disabled** |
| [`merge.py.deprecated`](/library/filter_plugins/merge.py.deprecated) | `merge_list_subsys`, `merge_dict_subsys`, `subsys_publish` | **deprecated, disabled** |
| [`mergeKeyed.py.deprecated`](/library/filter_plugins/mergeKeyed.py.deprecated) | `mergeKeyed` | **deprecated, disabled** |
| [`merge_strategy.py.deprecated`](/library/filter_plugins/merge_strategy.py.deprecated) | `merge_with_strategy` | **deprecated, disabled** |
