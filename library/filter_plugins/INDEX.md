# Filter Plugins — Reference Index

Custom Jinja2 filter plugins loaded by Ansible for compfuzor playbooks. Each
`.py` file in this directory defines a `FilterModule` class whose `filters()`
method returns a dict mapping the **registered filter name** (the name used in
Jinja, e.g. `{{ x | arrayitize }}`) to a Python callable. The registered name
sometimes differs from the filename.

This index documents all **30 registered filters** across 20 modules. Source
references are bundle-root-relative (e.g. [`merge.py`](/library/filter_plugins/merge.py)).

> **Convention key** — *Undefined/None handling*:
> - **tolerates undefined → X**: the function explicitly checks for
>   `AnsibleUndefined` (via `wrapped_test_undefined`) or `None` (via `_is_nothing`)
>   and returns `X` instead of raising.
> - **raises on undefined**: no such guard; a bare undefined reference either
>   raises at the Jinja call site (strict mode) or leaks through as an
>   `AnsibleUndefined` object. Not safe for missing inputs.

---

## Arrays / Lists

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `arrayitize` | `(*values)` | Wrap one or more args into a flat list; scalars → `[scalar]`, lists/tuples extended, `None`/bool/undefined dropped. | **tolerates undefined → `[]`** (single undefined arg returns `[]`; bool/None also collapse). | [`arrayitize.py:28`](/library/filter_plugins/arrayitize.py) |
| `listify` | `(value)` | Normalize a single value into a list; dict → `[{key,value}]` list, tuple → list, falsy → `[]`, scalar → `[scalar]`. | Raises on undefined — no `wrapped_test_undefined` guard, no `@accept_args_markers`. `None`/falsy → `[]` by `if not a[0]`, but a strict-undefined *reference* raises at the call site. | [`listify.py:5`](/library/filter_plugins/listify.py) |
| `concat` | `(*values)` | Variadic concatenation — runs each arg through `listify` and joins the results. | Raises on undefined — inherits `listify`'s behavior; each operand must be defined. | [`listify.py:17`](/library/filter_plugins/listify.py) |
| `rejectAny` | `(list, excluded)` | Generator filtering `list`, dropping any element present in `excluded`. | Raises on undefined — no guards; `a[0]`/`a[1]` must both be defined. | [`rejectAny.py:1`](/library/filter_plugins/rejectAny.py) |

**Examples**

```jinja
{{ "x" | arrayitize }}                 {# -> ["x"] #}
{{ undef_var | arrayitize }}           {# -> []  (tolerates undefined) #}
{{ [1,2] | concat([3], 4) }}           {# -> [1,2,3,4] #}
{{ [1,2,3,4] | rejectAny([2,4]) }}     {# -> [1,3] #}
```

---

## Dicts / Merging

The merge family is split across [`merge.py`](/library/filter_plugins/merge.py)
(the direct/subsys mergers), [`merge_strategy.py`](/library/filter_plugins/merge_strategy.py)
(the strategy-driven record merger), and [`mergeKeyed.py`](/library/filter_plugins/mergeKeyed.py)
(a compat shim).

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `dictify` | `(value)` | Normalize a mapping or list-shorthand into a dict: mapping passes through; list entries become `name: true` or overlay in. | **tolerates undefined/None → `{}`** (explicit `wrapped_test_undefined`). | [`dictify.py:18`](/library/filter_plugins/dictify.py) |
| `merge_list` | `(values, strategy="append", single=False, get=None)` | Merge direct list payloads with one list strategy (`append`, `append_unique`, or an op-dict/profile like `bins_generated`). | **tolerates undefined/None → `[]`** (`_is_nothing` filters each payload). | [`merge.py:412`](/library/filter_plugins/merge.py) |
| `merge_dict` | `(values=None, *extra, strategy="overlay", single=False, get=None, skip="none,undefined")` | Merge direct dict payloads left-to-right (later wins). Variadic extra dicts supported. `skip` controls which payloads are dropped. | **tolerates undefined/None → `{}`** (default `skip="none,undefined"` drops them before merging). | [`merge.py:449`](/library/filter_plugins/merge.py) |
| `merge_list_subsys` | `(current, subsystem_id=None, path="contrib.BINS", strategy="bins_generated", default=None, single=False, get=None, id=None, fallback_id=None, active=True, active_path="active")` *(context-injected)* | Merge `current` with one list value pulled from the `SUBSYSTEM` fact at `path`, gated by `active`. | **tolerates undefined/None** — undefined id/current handled via `_is_nothing`; missing subsystem → uses `default`. | [`merge.py:516`](/library/filter_plugins/merge.py) |
| `merge_dict_subsys` | `(current, subsystem_id=None, path="contrib.ENV", strategy="env_overlay", default=None, single=False, get=None, id=None, fallback_id=None, active=True, active_path="active", current_wins=True)` *(context-injected)* | Merge `current` with one dict value from `SUBSYSTEM`; `current_wins=True` puts current last so it overrides subsystem values. | **tolerates undefined/None** — same as `merge_list_subsys`. | [`merge.py:579`](/library/filter_plugins/merge.py) |
| `subsys_publish` | `(entry, subsystem_id=None, id=None)` *(context-injected)* | Deep-merge a new `entry` into `SUBSYSTEM[key]`, reading the fact through a raw-copy boundary so unrelated tagged strings stay unevaluated. | Raises on undefined — requires a non-empty `id`/`subsystem_id` (`AnsibleError` otherwise); undefined `entry` would propagate. | [`merge.py:647`](/library/filter_plugins/merge.py) |
| `merge_with_strategy` | `(records, strategies, aggregate=None, include_aggregate=True, payload_path=None, into=None, single=False, get=None)` | Per-field strategy merger over many records. Strategies: `append`, `append_unique`, `dict_overlay`, `replace`, nested maps, op-dicts (`merge_keyed`, `append_unique_by`), or named profiles. | Tolerates `None` (`_as_list`/`_as_dict` → `[]`/`{}`); **no `@accept_args_markers` and no undefined check** — a top-level undefined *reference* raises at the call site. | [`merge_strategy.py:200`](/library/filter_plugins/merge_strategy.py) |
| `mergeKeyed` | `(list1, list2, key="key", concat_fields=None)` | Compat shim — merges two lists of dicts by `key` via `merge_with_strategy` with `{op: merge_keyed}`. | Tolerates `None` operands (shim normalizes via `merge_with_strategy`); no explicit undefined guard. | [`mergeKeyed.py:11`](/library/filter_plugins/mergeKeyed.py) |
| `ignore_empty` | `(obj)` | Strip keys whose value is `None` or `''` from a dict. | Raises on undefined — calls `o.items()` with no guard; input must be a defined mapping. | [`ignore_empty.py:1`](/library/filter_plugins/ignore_empty.py) |

**Examples**

```jinja
{{ [existing, incoming] | merge_list("bins_generated") }}
{{ [defaults, overrides] | merge_dict("env_overlay") }}
{{ ENV | merge_dict_subsys("watchman") }}
{{ records | merge_with_strategy("subsystem_contrib", payload_path="contrib") }}
{{ {"a":1,"b":null,"c":""} | ignore_empty }}   {# -> {"a":1} #}
```

---

## Introspection / Undefined handling

Filters that absorb undefined/missing values so a pipeline doesn't abort.

| Filter | Signature | Purpose | Undefined/None | Source |
|---|---|---|---|---|
| `def` | `(value, fallback?)` | Replace undefined with `None`, or with `fallback` when given. | **tolerates undefined → `None`** (or the 2nd arg). | [`def.py:6`](/library/filter_plugins/def.py) |
| `truthy` | `(value, fallback?)` | Coerce to a real boolean; undefined → `False` (or `bool(fallback)`). | **tolerates undefined → `False`**. | [`def.py:16`](/library/filter_plugins/def.py) |
| `deflengthy` | `(value, fallback?)` | True iff value is list-like with `len > 0`; undefined → `False`. | **tolerates undefined → `False`**. | [`def.py:26`](/library/filter_plugins/def.py) |
| `get` | `(value, path, default=None)` | Safe dotted-path traversal through dicts/lists; missing segment, type mismatch, or undefined → `default`. | **tolerates undefined → `default`**. | [`get.py:56`](/library/filter_plugins/get.py) |
| `get_path` | `(value, path, default=None)` | Shared traversal implementation (also exposed directly). | **tolerates undefined → `default`**. | [`get.py:13`](/library/filter_plugins/get.py) |
| `has_var` / `has_vars` | `(item, prefix="", suffix="", returnLookedup=None, upper=False, lower=False)` *(context-injected)* | Look up a var (string) or filter a list of names against `vars` + `hostvars`, with prefix/suffix and case folding. | Returns `False`/missing rather than raising when a var is absent; raises `AnsibleError` if `item` is neither str nor list. | [`vars.py:20`](/library/filter_plugins/vars.py) |

**Examples**

```jinja
{{ maybe_undef | def([]) }}            {# -> [] #}
{{ maybe_undef | truthy }}             {# -> false #}
{{ record | get("a.b.c", "fallback") }}
{{ "FOO" | has_var(prefix="CFG_") }}
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
| `defaultDir` | `(path, defaultDir=False)` | Prefix `path` with `defaultDir/` unless it is already absolute (`/` or `~`). | Raises on undefined/missing `defaultDir` for relative paths (`raise "NoDefaultDir"`). | [`defaultDir.py:5`](/library/filter_plugins/defaultDir.py) |

> **Heads-up on `depostfix`** ([`deprefix.py:14`](/library/filter_plugins/deprefix.py)): it
> returns `path[:searchLen]` where `searchLen = len(match) + 1`, which **keeps one
> extra character** and drops nothing from the tail. This looks like an off-by-one
> bug compared to `deprefix`; verify before relying on it.

---

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
| `build_install_bins` | `(stem, basedir=False, src_root="../kernel")` | Emit standard `{build_bins, install_bins}` entries for a stem (e.g. `sysctl` → `build-sysctl.sh` / `install-sysctl.sh`). | Empty/whitespace stem → `{build_bins:[], install_bins:[]}`; no undefined guard. | [`build_install_bins.py:6`](/library/filter_plugins/build_install_bins.py) |
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

## Choosing a merger

Several filters overlap. Pick by **shape of input** and **whether operands may be undefined**.

### Normalize-to-list: `arrayitize` vs `listify`

| Need | Use | Why |
|---|---|---|
| Variadic, robust to undefined/None/bool, flattens lists | `arrayitize` | Explicit `wrapped_test_undefined`; single undefined → `[]`. Safe default. |
| Dict → `[{key,value}]` form, or single-arg only | `listify` | Only it produces the `{key,value}` shape; but **raises on strict-undefined**. |

### Concatenate lists: `concat` vs `merge_list`

| Need | Use | Why |
|---|---|---|
| Variadic join of already-defined lists/scalars | `concat` | Simple; but **raises on undefined operands** (delegates to `listify`). |
| Two-or-more payloads with dedupe / keyed merge / `bins_generated` profile, **and operands may be undefined** | `merge_list` | `_is_nothing` drops undefined/None payloads; supports `append_unique`, `merge_keyed`. |

### Merge dicts: `merge_dict` vs `dictify` vs `merge_with_strategy`

| Need | Use | Why |
|---|---|---|
| Turn list-shorthand or undefined into a dict | `dictify` | Normalizer, not a merger; undefined → `{}`. |
| Overlay two+ dicts, tolerate undefined operands | `merge_dict` | Default `skip="none,undefined"`; later wins. |
| Many records, **per-field strategies**, profiles (`subsystem_contrib`) | `merge_with_strategy` | Most powerful; but **no `@accept_args_markers`** — top-level undefined references raise at the call site. |

### Which list/dict mergers tolerate undefined/None?

**Robustly (explicit `wrapped_test_undefined` / `_is_nothing` guard):**

| Filter | Returns on all-undefined input |
|---|---|
| [`arrayitize`](/library/filter_plugins/arrayitize.py) | `[]` |
| [`dictify`](/library/filter_plugins/dictify.py) | `{}` |
| [`merge_list`](/library/filter_plugins/merge.py) | `[]` (or the `get` path's default) |
| [`merge_dict`](/library/filter_plugins/merge.py) | `{}` (default `skip="none,undefined"`) |
| [`merge_list_subsys`](/library/filter_plugins/merge.py) / [`merge_dict_subsys`](/library/filter_plugins/merge.py) | falls back to `default` / current unchanged when subsystem is missing or inactive |
| [`bin_composers`](/library/filter_plugins/bin_composers.py) | `[]` (local `_arrayitize`) |
| [`zim_fragment`](/library/filter_plugins/zim_fragment.py) | `[]` |

**Tolerate `None` but NOT a top-level undefined reference** (no `@accept_args_markers`,
no `wrapped_test_undefined`): [`concat`](/library/filter_plugins/listify.py),
[`listify`](/library/filter_plugins/listify.py),
[`merge_with_strategy`](/library/filter_plugins/merge_strategy.py),
[`mergeKeyed`](/library/filter_plugins/mergeKeyed.py).
A bare `{{ undef | concat(...) }}` will raise at the Jinja call site under strict
undefined before the filter body runs; an undefined *nested inside* a list/dict
operand leaks through unchanged.

**Raise on undefined** (no guards at all): [`rejectAny`](/library/filter_plugins/rejectAny.py),
[`ignore_empty`](/library/filter_plugins/ignore_empty.py),
[`subsys_publish`](/library/filter_plugins/merge.py) (requires a non-empty id).

---

## Module map

| File | Registered filters |
|---|---|
| [`arrayitize.py`](/library/filter_plugins/arrayitize.py) | `arrayitize` |
| [`bin_composers.py`](/library/filter_plugins/bin_composers.py) | `bin_composers` |
| [`build_install_bins.py`](/library/filter_plugins/build_install_bins.py) | `build_install_bins` |
| [`can_write.py`](/library/filter_plugins/can_write.py) | `can_write`, `has_write`, `should_become`, `diff_user`, `to_uid`, `to_gid` |
| [`cmdline.py`](/library/filter_plugins/cmdline.py) | `ansible_cmdline` |
| [`def.py`](/library/filter_plugins/def.py) | `def`, `truthy`, `deflengthy` |
| [`defaultDir.py`](/library/filter_plugins/defaultDir.py) | `defaultDir` |
| [`deprefix.py`](/library/filter_plugins/deprefix.py) | `deprefix`, `depostfix`, `deregex` |
| [`dictify.py`](/library/filter_plugins/dictify.py) | `dictify` |
| [`get.py`](/library/filter_plugins/get.py) | `get`, `get_path` |
| [`ignore_empty.py`](/library/filter_plugins/ignore_empty.py) | `ignore_empty` |
| [`listify.py`](/library/filter_plugins/listify.py) | `listify`, `concat` |
| [`merge.py`](/library/filter_plugins/merge.py) | `merge_dict`, `merge_dict_subsys`, `merge_list`, `merge_list_subsys`, `subsys_publish` |
| [`mergeKeyed.py`](/library/filter_plugins/mergeKeyed.py) | `mergeKeyed` |
| [`merge_strategy.py`](/library/filter_plugins/merge_strategy.py) | `merge_with_strategy` |
| [`passthrough_inspect.py`](/library/filter_plugins/passthrough_inspect.py) | `passthrough_inspect`, `materialize_dict`, `count_templates`, `merge_preserving` |
| [`rejectAny.py`](/library/filter_plugins/rejectAny.py) | `rejectAny` |
| [`template_render.py`](/library/filter_plugins/template_render.py) | `resolve` |
| [`unsafety.py`](/library/filter_plugins/unsafety.py) | `unsafety` |
| [`vars.py`](/library/filter_plugins/vars.py) | `has_var`, `has_vars` |
| [`zim_fragment.py`](/library/filter_plugins/zim_fragment.py) | `zim_fragment` |

**30 filters across 20 modules** (registered names verified against each
`FilterModule.filters()` return dict).
