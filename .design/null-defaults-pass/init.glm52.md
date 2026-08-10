---
type: Design
title: "Null/empty/default() cleanup pass across tasks/"
description: Survey of 512 default() / 82 is-defined sites in tasks/, with migration recipes and proposed filter wins.
resource: /design/null-defaults-pass/init.glm52.md
tags: [refactor, jinja, filters, tasks]
status: draft
generated: { by: llm:glm-5.2, at: 2026-08-04T00:00:00Z }
sources:
  - id: library-readme
    resource: /library/README.md
    title: Ansible Plugin Reference
  - id: def-py
    resource: /library/filter_plugins/def.py
    title: "def / truthy / deflengthy filters"
  - id: cfmerge-py
    resource: /library/filter_plugins/cfmerge.py
    title: "normalize / merge_list / merge_dict / combine_iff / join2"
---

# Null / empty / `default()` cleanup pass across `tasks/`

## Stage setting

The cfmerge era landed a generation of filters and tests that **tolerate
undefined** via `@accept_args_markers` ([`def.py:6`](/library/filter_plugins/def.py),
[`cfmerge.py`](/library/filter_plugins/cfmerge.py)). That makes the bulk of
`|default(...)` calls in `tasks/` either redundant or replaceable with a
shorter, intent-revealing idiom. This doc inventories every recurring pattern,
gives a concrete migration recipe for each, and proposes a handful of new
filters that would collapse the most repetitive remaining sites.

### Scope of the survey

Ran across `tasks/` only (not the `.pb` playbooks or `library/`). The
heavy-hitter files (each with 7+ `default(False)` alone) are:

- [`tasks/compfuzor.includes`](/tasks/compfuzor.includes) — 31 (the master dispatcher)
- [`tasks/compfuzor/fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks) — 13
- [`tasks/compfuzor/repo_git.tasks`](/tasks/compfuzor/repo_git.tasks) — 12
- [`tasks/compfuzor/vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks) — 10
- [`tasks/compfuzor/bins.tasks`](/tasks/compfuzor/bins.tasks) — 8
- [`tasks/compfuzor/fs_env.tasks`](/tasks/compfuzor/fs_env.tasks) — 7
- [`tasks/compfuzor/vars_src.tasks`](/tasks/compfuzor/vars_src.tasks) — 6

### The headline numbers

| Pattern | Count | Notes |
|---|---|---|
| `default(...)` total | **512** | everything below rolls up to this |
| `default(False)` / `default(True)` | 136 | bypass- & feature-flag guards |
| `default([])` | 44 | many are redundant on top of `normalize`/`merge_*` |
| `is defined` | 82 | task `when:` guards + inline conditionals |
| `COMFUZOR_SHOULD_BECOME\|default(BECOME\|default(...))` chain | 34 | single most repeated expression in repo |
| `should_become(OWNER\|default(), ...)` invocation | 26 | always paired with the chain above |
| `X\|default(Y)\|default(Z)` fallthrough chains | 24 | two-stage defaults |
| `item.X\|default(item.Y\|default(item))` | 24 | item-shape normalization |
| `TYPE\|default(NAME)` | 18 | subsystem-name fallback |
| `\|def` (new filter) already in use | 17 | migration is partially done |
| `default(none, true)` | 14 | ternary-feeding owner/group |
| `.stdout\|default(0)\|int` | 8 | register-output coercion |
| `files/{{TYPE\|default(NAME)}}` path | 7 | template-src fallback |
| `is defined and ... is mapping` | 3 | shape-test sequences |

### What "tolerates undefined" means here

Filters/tests decorated with `@accept_args_markers` **absorb** Ansible
undefined markers without raising. So `FOO|truthy` returns `False` when `FOO`
is undefined — no `default(False)` needed. The full set, from
[`library/README.md`](/library/README.md):

- **Filters**: `def`, `truthy`, `deflengthy`, `get`/`get_path`, `normalize`,
  `join2`, `merge_list`, `merge_dict`, `merge_fields`, `combine_iff`,
  `tag_each`, `resolve`, `when`/`whenAnd`, `ignore_empty` (raises — outlier)
- **Tests**: `deftruthy`, `deffalsy`, `defmapping`, `deflengthy`, `having`,
  `havingany`

Tests are the underused half of this toolkit. `compfuzor.includes` already
mixes `is deflengthy`, `is defmapping`, `is truthy`, and `is falsy` with the
old `|default(False) is truthy` form inconsistently — that file alone is a
good demonstration of where we're headed.

---

## Pattern catalog & migration recipes

### P1 — Bypass-flag guards (the biggest bucket)

The bypass-flag convention from [`AGENTS.md`](/AGENTS.md) (`PKGS_BYPASS`,
`SYSTEMD_THUNK_BYPASS`, …) produces the most repeated `default(False)` sites.
Three coexisting idioms today:

```yaml
when: not PKGS_BYPASS|default(False)                       # raw
when: PKGS_BYPASS|default(False) is falsy                  # mixed
when: PKGS_BYPASS|default(False) is not truthy             # mixed
```

**All three become**:

```yaml
when: PKGS_BYPASS is deffalsy
```

Examples from [`tasks/compfuzor.includes`](/tasks/compfuzor.includes):

- L145: `not FS_BYPASS|default(False)` → `FS_BYPASS is deffalsy`
- L155: `not BINS_BYPASS|default(False)` → `BINS_BYPASS is deffalsy`
- L161: `LINKS|default(False) is truthy and LINKS_BYPASS|default(False) is falsy` → `LINKS is deftruthy and LINKS_BYPASS is deffalsy`
- L167: `FS_BYPASS|default(False) is falsy` → `FS_BYPASS is deffalsy`
- L174–188, L200: every `not *_BYPASS|default(False)` → `*_BYPASS is deffalsy`

And from elsewhere:

- [`vars_systemd_unit.tasks:29,84,164,191,214,225`](/tasks/compfuzor/vars_systemd_unit.tasks) — 6× `not SYSTEMD_INSTALL_BYPASS|default(False)` → `SYSTEMD_INSTALL_BYPASS is deffalsy`
- [`fs_srcs_too.tasks:12,20,29`](/tasks/compfuzor/fs_srcs_too.tasks) — `OPT_DIR|default(False)`
- [`fs_env.tasks:101`](/tasks/compfuzor/fs_env.tasks) — `ENV_IS_EXPORT|default(False)` → `ENV_IS_EXPORT is deftruthy`

**Net**: ~43 bypass-flag sites + ~80 more `default(False)` flag sites collapse
to a test. Drops ~120 of the 136 `default(False|True)` occurrences.

### P2 — `default(False)` feeding a `truthy`/`bool`/`ternary` (pure noise)

Anywhere the default exists only to keep a downstream truthiness test from
raising. Replace with the `truthy` filter or `deftruthy`/`deffalsy` test.

```yaml
# before
when: FS_CONTAINERED|default(False)|ternary(relative, fsh)     # fs_hierarchy.tasks:5
mode: "{{item.copyDir|default(False) == True}}"                # fs_hierarchy.tasks:123
when: SERVICE_DIR|default(False) is truthy

# after
when: FS_CONTAINERED|truthy|ternary(relative, fsh)             # or: FS_CONTAINERED|truthy(True) for default-true
mode: "{{item.copyDir is deftruthy}}"
when: SERVICE_DIR is deftruthy
```

Hot spots:

- [`fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks) L5,6,36,38,43,63,79,98,118,156 (`COMFUZOR_SHOULD_BECOME|default(BECOME|default(should_become))|bool` is its own pattern — see P7)
- [`bins.tasks:10,41,55,56,70`](/tasks/compfuzor/bins.tasks)
- [`vars_systemd_unit.tasks:11-14`](/tasks/compfuzor/vars_systemd_unit.tasks) — the `_systemd_has_*` probes
- [`systemd.thunk.tasks:13,17,23,28`](/tasks/systemd.thunk.tasks) — `not USERMODE|default(False) and not SYSTEMD_USERMODE|default(False)` → `(USERMODE is deffalsy and SYSTEMD_USERMODE is deffalsy)`.

### P3 — `default([])` feeding a filter that already tolerates undefined

These are **pure wins** — drop the default entirely.

```yaml
# before
with_items: "{{ BINS|default([]) }}"
loop:      "{{ _vals.files|default([], true) }}"
when:      ENV_LIST|default([], true)|normalize(to='list')|length > 0

# after
with_items: "{{ BINS|normalize(to='list') }}"
loop:      "{{ _vals.files|normalize(to='list') }}"
when:      ENV_LIST|normalize(to='list')|length > 0
```

Hot spots:

- [`bins.tasks:20,36,68`](/tasks/compfuzor/bins.tasks) — `BINS|default([])`
- [`fs_hierarchy.tasks:110,131,168`](/tasks/compfuzor/fs_hierarchy.tasks) — `_vals.files|default([])`, `_vals.files|default([], true)`, `_vals.d|default([], true)`
- [`compfuzor.includes:135,136`](/tasks/compfuzor.includes) — the `ENV_*_LIST|default([], true)|normalize(to='list')` chains
- [`repo_git.tasks:49,51,63,65`](/tasks/compfuzor/repo_git.tasks) — `git_repos|default([])|length > 0`
- [`gen_passwords.tasks:40,60,66,78,84,90,106,127,132,133,135,141,148`](/tasks/compfuzor/gen_passwords.tasks) — `PASSWORDS|default([])` repeated 13 times; the entire file is one big P3 site.

**`gen_passwords.tasks` special case**: the file already guards its play with
`when: PASSWORDS|default([])|length > 0` (L84). Every downstream
`PASSWORDS|default([])` is unreachable-undef — drop all of them.

### P4 — `default({})` for `combine`/`merge_dict` seeds

```yaml
# before
_systemd_has_service: "{{ SYSTEMD_SERVICE|default(false) or (SYSTEMD_SERVICES|default({}))|length > 0 }}"
_raw_vars_base: "{{ (lookup('vars', SYSTEMD_VARS_ROOT, default={}) if SYSTEMD_VARS_ROOT is defined else {}) | combine({'target': target} if target is defined else {}) }}"

# after — merge_dict tolerates undefined layers
_systemd_has_service: "{{ SYSTEMD_SERVICE is deftruthy or SYSTEMD_SERVICES|deflengthy }}"
_raw_vars_base: "{{ {} | merge_dict(SYSTEMD_VARS_ROOT lookup, {'target': target} if target is defined else {}) }}"
```

The `combine({'k': v} if v is defined else {})` boilerplate on
[`vars_systemd_unit.tasks:58`](/tasks/compfuzor/vars_systemd_unit.tasks) is
**exactly** what `combine_iff` was added for — see
[`library/README.md`](/library/README.md) entry. Same for L132–134, L178, and
the four duplicated `combine_iff`-shaped sites in
[`fs_env.tasks`](/tasks/compfuzor/fs_env.tasks).

### P5 — `X|default(Y)|default(Z)` fallthrough chains

24 sites. Two-stage defaults exist because Ansible's `default` only takes one
fallback. The fix is to **upgrade `def` to variadic semantics**: return the
first non-undefined argument, or `None` if all are undefined.

```python
# library/filter_plugins/def.py — new un_undefine
@accept_args_markers
def un_undefine(*a):
    """First non-undefined argument, else None.

    Generalizes the old binary def(X, Y). A literal final fallback
    (def(X, Y, 'default')) works because literals are always defined.
    """
    for candidate in a:
        if not wrapped_test_undefined(candidate):
            return candidate
    return None
```

**Backward compatibility**:
- `X|def` (1 arg): unchanged. X defined → X; X undefined → None.
- `X|def(Y)` (2 args): X defined → X; X undefined & Y defined → Y; **both
  undefined → None**. The current implementation returns Y's undefined
  marker in that case — this is a strict improvement (fixes a latent bug).
- `X|def(Y, Z, ...)` (3+ args): new capability.

Migration:

```yaml
# before
XDG_DATA_HOME: "{{XDG_DATA_HOME|default(COMPFUZOR_BASE.stdout_lines[11]|default(HOMEDIR + '/.local/share', True), True)}}"

# after
XDG_DATA_HOME: "{{ XDG_DATA_HOME|def(COMPFUZOR_BASE.stdout_lines[11], HOMEDIR + '/.local/share') }}"
```

Sites that are legitimate two-stage (var → register → literal) all collapse
to one `def(...)` call with N positional args. Hot spots:
[`vars_base.tasks:69-75`](/tasks/compfuzor/vars_base.tasks) (XDG chain),
[`vars_base.tasks:112`](/tasks/compfuzor/vars_base.tasks) (PREFIX_DIR chain),
[`systemd.unit.includes:38`](/tasks/systemd.unit.includes).

### P6 — `TYPE|default(NAME)` (subsystem-name fallback, 18 sites)

Extremely repetitive. Either:

1. **Resolve once** in [`vars_base.tasks`](/tasks/compfuzor/vars_base.tasks).
   It already sets `TYPE` and `NAME` as facts. The fallback
   `TYPE|default(NAME)` is needed only because some playbooks are imported
   with `TYPE` truly absent. Fix it at the source: in `vars_base.tasks`,
   `TYPE: "{{TYPE|default(name_)}}"` (already there at L86) should mean
   `TYPE` is **always** defined downstream. Verify and then delete all 18
   `TYPE|default(NAME)` sites.
2. **If the early-set guarantee can't be proven**, add a `SUBSYSTEM` fact
   explicitly and migrate call sites to it.

Same logic for `NAME|default(TYPE)` (the reverse direction) and
`files/{{TYPE|default(NAME)}}/` path prefixes (7 sites).

### P7 + P8 — The become-chain monster, merged with owner/group resolution

This expression, or a near-identical variant, appears **34 times**:

```yaml
become: "{{ COMFUZOR_SHOULD_BECOME|default(BECOME|default(_dest|should_become(OWNER|default(), _cf_user_id, GROUP|default(), _cf_user_gid)))|bool }}"
```

And it is always paired with the owner/group resolution pattern (P8, 14+
sites, 24 in `fs_hierarchy.tasks` alone):

```yaml
owner: "{{do_become|ternary(owner|default(_cf_user_id, true),omit)}}"
group: "{{do_become|ternary(group|default(_cf_user_gid, true),omit)}}"
```

The two are the same computation: given a path and optional OWNER/GROUP,
decide whether to `become`, and resolve the effective owner/group. Today
they're computed redundantly — `become:` re-derives what `owner:`/`group:`
also derive. **Merge into a single filter that returns all three.**

**Proposal**: a context-injected `become_calc(path, owner=OWNER, group=GROUP)`
filter returning `{become: bool, owner, group}`. Standardize on a `_become`
variable convention so task files read uniformly:

```yaml
- name: ...
  file:
    path: "{{ _dir }}"
    state: directory
    owner: "{{ _become.owner }}"
    group: "{{ _become.group }}"
  become: "{{ _become.become }}"
  vars:
    _become: "{{ _dir|become_calc }}"
```

The filter resolves, in order:
1. `become`: `COMFUZOR_SHOULD_BECOME` → `BECOME` → `should_become(path, owner, group, _cf_user_id, _cf_user_gid)`
2. `owner`: `owner` arg (defaults to scope `OWNER`) → `_cf_user_id`, or `omit` when `become` is falsy
3. `group`: `group` arg (defaults to scope `GROUP`) → `_cf_user_gid`, or `omit` when `become` is falsy

Context-injection via `@pass_context` (same pattern as
[`vars.py:19`](/library/filter_plugins/vars.py)) gives the filter access to
`COMFUZOR_SHOULD_BECOME`, `BECOME`, `OWNER`, `GROUP`, `_cf_user_id`,
`_cf_user_gid` without threading them through every call site.

This collapses P7's 34 sites **and** P8's 24+ sites in one stroke, and
removes the redundant re-derivation of owner/group inside `become:`'s
`should_become(...)` call. `_become` is a convention, not a contract — task
files that don't adopt it keep working.

### P9 — `item.X|default(item.Y|default(item))` (24 sites)

Item-shape normalization. Same variadic-`def` fix as P5:

```yaml
# before
src:  "{{ item.src|default(item.name|default(item, true), true)|defaultDir(srcDir) }}"
dest: "{{ item.dest|default(item.name|default(item.src|default(item, true), true), true)|defaultDir(...) }}"

# after
src:  "{{ item.src|def(item.name, item)|defaultDir(srcDir) }}"
dest: "{{ item.dest|def(item.name, item.src, item)|defaultDir(...) }}"
```

**Prerequisite**: make `defaultDir` tolerate undefined. Today it raises on
undefined input ([`library/README.md`](/library/README.md) notes this). Once
`defaultDir(undefined, base)` returns `base` instead of raising, the
trailing `item` fallback can be dropped at sites where the basename isn't
actually wanted:

```yaml
src: "{{ item.src|def(item.name)|defaultDir(srcDir) }}"
```

Sites that genuinely want "fall back to the item itself" keep the three-arg
form. The `defaultDir` change is small (one guard at the top of
[`defaultDir.py:5`](/library/filter_plugins/defaultDir.py)) and unblocks
cleaner P9 expressions as a follow-on.

### P10 — `.stdout|default(0)|int` register coercion (8 sites) — rejected

No real win over the existing idiom; leave as-is. Not worth churning just
to swap `default` for `def`.

### P11 — `is defined` task guards (P11a) vs inline conditionals (P11b)

**P11a — task `when:` guards**, mostly legitimate. `when: PASSWORDS is
defined` on [`compfuzor.includes:21`](/tasks/compfuzor.includes) is the
correct way to gate an `import_tasks` on optional input. Leave these. The
only ones worth touching are the "defined and truthy" compounds:

```yaml
# before
when: X is defined and X
when: X is defined and (X is mapping or ...)

# after
when: X is deftruthy
when: X is defmapping or ...
```

**P11b — inline `{{ X if X is defined else Y }}`** is the old shape of
`X|default(Y)` or `X|def(Y)`. Migrate. Examples:

- [`vars_base.tasks:106-108`](/tasks/compfuzor/vars_base.tasks) —
  `{{'-' if INSTANCE else ''}}{{INSTANCE|default('')}}` →
  `{{'-' if INSTANCE is deftruthy else ''}}{{INSTANCE|def('')}}`
- [`bins.tasks:70`](/tasks/compfuzor/bins.tasks) — compound inline guard

**P11c — `{% if X is defined %}` inside Jinja blocks**. These are inside
`{% set ns = namespace(...) %}` accumulator loops (see
[`vars_systemd_unit.tasks:131-144,193-205`](/tasks/compfuzor/vars_systemd_unit.tasks),
[`gen_passwords.tasks`](/tasks/compfuzor/gen_passwords.tasks)). They're the
correct tool inside a loop — leave them, but where the body is just appending
to a list, consider `merge_list`/`tag_each` instead of the hand-rolled loop.

### P12 — `default(omit, true)` (only 1 site in tasks/)

[`fs_hierarchy.tasks:54`](/tasks/compfuzor/fs_hierarchy.tasks):
`DIRMODE|default(omit, true)`. Legitimate — the `omit` semantic can't be
reproduced by the new filters. Leave.

### P13 — `lookup('vars', X, default=...)` (41 sites)

Not a `default()` filter call, but the same conceptual role. The idiom is
correct for dynamic var lookup. Modernization candidates:

- Where the default is `False`/`{}`/`[]` and the consumer immediately
  truthiness-tests, consider `X|def` or `X|truthy` at the use site instead of
  pre-resolving. But the dynamic-name case (`'SYSTEMD_'+t|upper`) can't be
  replaced by a filter — `lookup('vars', ...)` is required.
- [`fs_hierarchy.tasks:30-38`](/tasks/compfuzor/fs_hierarchy.tasks) — the
  `vals` dict pre-resolves six names with `default=False` then tests them.
  This is fine; the structure enables `_vals.sDir` etc. as a clean API.

---

## Proposed changes

Three concrete pieces of work, in dependency order.

### C1 — Variadic `def` (library) ⭐⭐⭐ ✓ DONE

Upgrade [`def.py:6`](/library/filter_plugins/def.py) `un_undefine` to walk
positional arguments and return the first non-undefined one. See P5 for the
implementation sketch and backward-compat analysis (short version: 1- and
2-arg behavior preserved; 2-arg-both-undefined case is a latent-bug fix).

**Status**: shipped + 18 unit tests. Also enhanced with `falsy=` parameter
(see C1b below).

### C1b — `def(falsy=)` parameter (library) ⭐⭐⭐

Extends variadic `def` to also skip falsy values, matching the
`default(X, true)` semantic that `def` alone can't replicate:

- `def(X, Y)` — first non-undefined (existing)
- `def(X, Y, falsy=True)` — first non-undefined AND Python-truthy. Matches
  `X|default(Y, true)`: None, `''`, `0`, `False`, `[]`, `{}` all skip.
- `def(X, Y, falsy=[None, ''])` — first non-undefined AND not in the
  caller-supplied skip list. For when you want to skip empty strings but
  keep `0` or `False`.

Unblocks the `default(X, true)` family: XDG register chains, empty-string
guards, and any other "default on falsy too" site that's not owner/group
(P7+P8 handles those via become_calc).

**Unblocks**: XDG chains in `vars_base.tasks:69-75`, and ~15 other
`default(X, true)` sites across tasks/.

### C2 — `defaultDir` tolerates undefined (library) ⭐

Add an undefined guard at the top of
[`defaultDir.py:5`](/library/filter_plugins/defaultDir.py): when the input
is undefined, return the `defaultDir` argument unchanged (or raise if
`defaultDir` itself is missing — same as today's relative-path behavior).
Lets P9 sites drop the trailing `item` fallback where it isn't meaningful.

### C3 — `become_calc(path, owner=OWNER, group=GROUP)` filter (library) ⭐⭐⭐

**Prototyped and tested.** See [`library/filter_plugins/become.py`](/library/filter_plugins/become.py)
+ [`tests/filter_plugins/become.test.py`](/tests/filter_plugins/become.test.py)
(18 unit tests) and the live-Ansible probe at
[`.test-agent/become-calc/probe.pb`](/.test-agent/become-calc/probe.pb) (6
scenarios). All pass.

Context-injected via `@pass_context`. Returns
`{become, owner, group}` computed once from `COMFUZOR_SHOULD_BECOME` →
`BECOME` → `should_become(...)`, with `owner`/`group` resolved from the
filter args (defaulting to scope `OWNER`/`GROUP`) and `_cf_user_id` /
`_cf_user_gid`, and `omit` applied to owner/group when `become` is false.

**Key implementation discovery**: `context.get("vars", {})` (the pattern
[`vars.py:37`](/library/filter_plugins/vars.py) uses) is **deprecated** in
ansible-core 2.21 and removed in 2.24. The prototype uses
`context.get_all()` instead, which returns the full merged scope (play +
role + task vars) without touching the deprecated magic. **`vars.py` needs
the same migration** — separate cleanup, but flagged by this work.

**Subtlety encoded in tests** (the falsy matrix):
- Boolean keys (`COMFUZOR_SHOULD_BECOME`, `BECOME`): only *absent* or
  *undefined* falls through. `None` is treated as present-and-falsy (matches
  `X|default(Y)` without the `true` flag).
- Owner/group keys (`OWNER`, `GROUP`): absent, undefined, `None`, or `""`
  all fall through (matches `X|default(Y, true)`).
- The probe call sees `None` for "no owner specified" (should_become's
  `good()` handles it); the *final* `owner_val` falls back to `_cf_user_id`
  when become is true.

Standardize on a `_become: "{{ path|become_calc }}"` convention in `vars:`
blocks. See P7+P8 for the full shape.

**Collapses**: 34 become-chains + 24+ owner/group chains, and removes the
redundant re-derivation of owner/group inside the become expression itself.

### Rejected proposals (for the record)

- **W3 `bypass(*names)` test** — rejected. Stay explicit; `*_BYPASS is deffalsy`
  reads fine and keeps the convention visible at each site.
- **W4 `is usermode` test** — rejected. `USERMODE is deftruthy or
  SYSTEMD_SCOPE == 'user'` is already readable.
- **W5 Lift bypass defaults into `vars/common.yaml`** — rejected. Task files
  should be explicit about the inputs they consume; we don't want a calling
  contract where `PKGS_BYPASS` etc. must be pre-defined by the includer.
  Each `is deffalsy` site carries its own default semantics.
- **W6 `stdout_int` helper** — rejected. No win over the existing idiom.
- **`pick_first(*keys)` filter** — folded into C1. The variadic `def` covers
  both P5 and P9 with one primitive instead of two.

---

## Suggested sequencing

Each step is independently shippable.

1. **C1 — variadic `def`**. Library-only change, covered by existing `def`
   tests in [`tests/filter_plugins/`](/tests/filter_plugins/) (add cases for
   3+ args and all-undefined). Unblocks P5 and P9 mechanically.
2. **P5 sweep** — `X|default(Y)|default(Z, true)` → `X|def(Y, Z)`. Start with
   [`vars_base.tasks:69-75`](/tasks/compfuzor/vars_base.tasks) (the XDG
   chain) — single file, easy review.
3. **P1 sweep** — `not FOO_BYPASS|default(False)` → `FOO_BYPASS is deffalsy`
   and `FOO|default(False) is truthy` → `FOO is deftruthy`. ~120 sites across
   [`compfuzor.includes`](/tasks/compfuzor.includes),
   [`vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks),
   [`fs_srcs_too.tasks`](/tasks/compfuzor/fs_srcs_too.tasks),
   [`systemd.thunk.tasks`](/tasks/systemd.thunk.tasks). Mechanical.
4. **P3 sweep** — drop `default([])` where downstream is
   `normalize`/`merge_*`/`deflengthy`. Start with
   [`gen_passwords.tasks`](/tasks/compfuzor/gen_passwords.tasks) (13 sites,
   one file).
5. **P4 sweep** — `combine({'k': v} if v is defined else {})` → `combine_iff`
   in [`vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks)
   and [`fs_env.tasks`](/tasks/compfuzor/fs_env.tasks).
6. **P6** — delete the 18 `TYPE|default(NAME)` sites. Pre-audit confirms
   `TYPE` is always set as a fact by
   [`vars_base.tasks:86`](/tasks/compfuzor/vars_base.tasks) before any
   consumer runs.
7. **C2 — `defaultDir` undefined-tolerance**. Library change with unit tests.
8. **P9 sweep** — `item.X|default(item.Y|default(item, true), true)` →
   `item.X|def(item.Y, item)` (or `item.X|def(item.Y)` at sites that don't
   want the item fallback, now that `defaultDir` tolerates undefined).
9. **C3 — `become_calc` filter**. Library change; needs unit tests covering
   the three resolution branches and the `omit`-on-false-become behavior.
10. **P7+P8 sweep** — introduce `_become: "{{ path|become_calc }}"` and
    migrate the 34+24 sites. Largest single readability win in the pass.
11. **P11b** — inline `{{ X if X is defined else Y }}` → `X|def(Y)`. Small,
    scattered, do alongside other sweeps.

Steps 1–6 need no new filters beyond the variadic `def` and delete ~250
`default()` sites.

---

## Open questions

- **`def` 2-arg both-undefined behavior change** — **resolved**. The current
  `def.py` returns the second arg's undefined marker when both are undefined;
  the variadic version returns `None`. Audited the 17 existing `|def` sites:
  all use either bare `|def` (1-arg, coerce-to-None) or `|def('')` (2-arg
  with a literal). None rely on the marker leaking through. Safe.
- **`become_calc` context-injection** — **resolved by prototype**.
  `@pass_context` + `context.get_all()` sees task-level `vars:` blocks
  (verified by probe 6 in
  [`.test-agent/become-calc/probe.pb`](/.test-agent/become-calc/probe.pb)).
  Bonus discovery: `context.get("vars", {})` is deprecated in ansible-core
  2.21 / removed in 2.24; `vars.py` needs the same `get_all()` migration.
- **`_become` vs `do_become` naming** — **resolved**. `do_become` is already
  used in [`fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks) and
  elsewhere as the resolved *boolean*. The proposed struct should use a
  distinct name to avoid confusion: `_become` (struct) vs `do_become`
  (bool). `_become` itself is free in `tasks/` — no collisions found. The
  distinction is load-bearing: `_become.become == do_become` after
  resolution; `_become.owner` / `_become.group` are the new fields.
- **`defaultDir` undefined-return semantics**: when input is undefined and
  `defaultDir` arg is provided, return the arg as-is? Or join as if input
  were empty string? The former is cleaner (treat undefined as "no basename,
  use the dir directly"). Confirm before implementing C2.
- **P11c dynamic `lookup('vars', ...)` audit**: out of scope for this pass,
  but worth a follow-up sweep to confirm no stale pre-cfmerge dynamic-lookup
  patterns remain.
