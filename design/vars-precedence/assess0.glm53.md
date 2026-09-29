# vars-precedence: assessment of common.yaml loading vs Ansible precedence

Status: assessment only (wave `assess0`, model glm53, 2026-09-29). No behavior, code, or
template changes proposed here beyond named options; this document maps the option space
requested after the rust_bins integration-test failure.

## Situation

Compfuzor renders deployments from flat playbooks named `<name>.<type>.pb`. Identity
(NAME/TYPE/INSTANCE/DIR) is derived in two places: eagerly-ish templates at the top of
[`vars/common.yaml`](/vars/common.yaml) (loaded in production by the custom
`include_defaults` action), and a second, independent derivation in the `set_fact` layer of
[`tasks/compfuzor/vars_base.tasks`](/tasks/compfuzor/vars_base.tasks). An integration test
loaded `common.yaml` through stock `vars_files:` with `TYPE: opt` as a play var and failed
with `Error while resolving value for 'BINS': object of type 'dict' has no attribute
'type'`. The operator's concern: common.yaml outweighing play vars feels wrong, and a
custom loader may be fighting ansible's core. This assessment confirms the mechanics from
installed source (ansible-core 2.21.0, python 3.14, `/usr/lib/python3/dist-packages/ansible`)
and evaluates the option space.

## What happened (the incident)

- During work on the rust bins lane (jj `zrozruywlwsk`),
  [`tests/integration/rust_bins.test.py`](/tests/integration/rust_bins.test.py) rendered a
  temp playbook named `render.pb` that loaded `vars/common.yaml` via stock `vars_files:`
  and declared `TYPE: opt` as a play var (lines 34-37).
- In ansible-core, **`vars_files` outranks play `vars`**, so common.yaml's
  `TYPE: "{{ (lookup('file','/proc/self/cmdline') | ... | ansible_cmdline).type }}`
  ([common.yaml:4](/vars/common.yaml)) shadowed the play var.
- The test then ran `lookup('merge_subsys', id='rust', contrib='BINS')`
  (rust_bins.test.py:49-50). The rust contrib BINS embed a `{{ TYPE }}` leaf
  (`INSTALL_BIN="${RUST_BIN:-{{ TYPE }}}"`, [common.yaml:466](/vars/common.yaml)), and
  merge_subsys returns `self._templar._engine.template(result)`
  ([merge_subsys.py:328](/library/lookup_plugins/merge_subsys.py)) — a **top-level**
  template call, which 2.21 finalizes recursively, rendering embedded templates.
- `render.pb` does not match the two-segment `<type>.<instance>.pb` pattern, so the
  `ansible_cmdline` filter returns `{}` ([cmdline.py:14-15,33-35](/library/filter_plugins/cmdline.py)).
  Jinja `.type` on `{}` fails attribute and item lookup, producing a `Marker` whose hint is
  `object of type 'dict' has no attribute 'type'`, raised as `AnsibleUndefinedVariable`.
- The task-arg finalization chain wrapping the `set_fact`'s `BINS` arg converts that to
  `Error while resolving value for 'BINS'`.
- Workaround committed: pass `-e TYPE=opt -e NAME=fixture` (rust_bins.test.py:59-62, with
  an explanatory comment). Extra vars outrank `vars_files`.
  [`tests/integration/links.test.py`](/tests/integration/links.test.py) had already adopted
  the same workaround (lines 93-94).

## Confirmed mechanics (installed ansible-core 2.21.0 source)

### Where vars_files beats play vars

`VariableManager.get_vars` builds the stack in this order (all citations
`/usr/lib/python3/dist-packages/ansible/vars/manager.py`):

| Layer | Position | Citation |
|---|---|---|
| role defaults (play-level `roles:`) | lowest | manager.py:215-218 |
| task's own role defaults (during role tasks) | | manager.py:234-235 |
| inventory group/host vars + vars plugins (per `VARIABLE_PRECEDENCE`) | | manager.py:289-299 |
| **persistent fact cache** (facts) | | manager.py:301-318 |
| **play `vars:`** | | manager.py:320-321 |
| **play `vars_files:`** | beats play vars | manager.py:323-360 |
| role exported vars (play context) | | manager.py:385-388 |
| task vars (role/task/include) | | manager.py:393-397 |
| include_vars layer (`_vars_cache`) | | manager.py:401-403 |
| set_fact / register (ephemeral facts) | | manager.py:404-405 |
| role params / include params | | manager.py:407-414 |
| **extra vars (`-e`)** | highest (below magic) | manager.py:416-417 |

Two 2.21-specific details on the vars_files path:

- Files load with `trusted_as_template=True` (manager.py:357) — vars_files contents are
  trusted for later templating, which is why common.yaml's templates stay live in the layer
  instead of erroring at load.
- `combine_vars` under default hash behavior is plain dict union (`a | b`,
  `/usr/lib/python3/dist-packages/ansible/utils/vars.py:78-89`): a vars_files key
  **wholesale-replaces** the play var. No merge knob rescues the play var; only `-e`
  (manager.py:417) outranks vars_files.

### The error shapes

- `Error while resolving value for {key!r}` — raised by `ChainTemplar.get`
  (`/usr/lib/python3/dist-packages/ansible/_internal/_templating/_chain_templar.py:34-39`).
  The task-arg variant (`TaskArgsChainTemplar`,
  `/usr/lib/python3/dist-packages/ansible/_internal/_task.py:413-426`) is what names the
  `set_fact` argument `BINS`.
- `object of type 'dict' has no attribute 'type'` — the `Marker` hint
  (`/usr/lib/python3/dist-packages/ansible/_internal/_templating/_jinja_common.py:77-78`),
  created when the sandboxed `getattr` attribute→item fallback both fail
  (`/usr/lib/python3/dist-packages/ansible/_internal/_templating/_jinja_bits.py:807-836`).
- Why the lookup forces materialization: top-level `template()` calls finalize recursively
  — "renders any embedded templates and triggers Marker behaviors"
  (`/usr/lib/python3/dist-packages/ansible/_internal/_templating/_engine.py:302-305,
  311-321`). merge_subsys's final line is such a call
  ([merge_subsys.py:328](/library/lookup_plugins/merge_subsys.py)); its raw-copy helpers
  ([template_data.py:43-67](/library/filter_plugins/template_data.py),
  [merge_subsys.py:232](/library/lookup_plugins/merge_subsys.py)) exist precisely to *avoid*
  forcing earlier, but the exit render cannot defer.

### Task-arg finalization (2.21) and what it means for a custom loader

`Task._post_validate_args` runs every task's args through `TaskArgsFinalizer`
(`/usr/lib/python3/dist-packages/ansible/playbook/task.py:182-235`; finalizer at
`/usr/lib/python3/dist-packages/ansible/_internal/_task.py:429-461`). An action plugin can
customize per-arg templating via the (explicitly experimental) `finalize_task_arg` /
`get_finalize_task_args_context` hooks
(`/usr/lib/python3/dist-packages/ansible/plugins/action/__init__.py:267-287`). Constraint
for any extended loader: its own `file:` arg arrives already templated, and any failure
inside arg resolution surfaces with the `Finalization of task args ... failed` /
`Error while resolving value for ...` wrappers — debugging gets noisier the deeper the
loader leans on templated args.

### Where set_fact / include_vars / ansible_facts sit — and a 2.21 surprise

Stock `include_vars` registers results into `VariableLayer.INCLUDE_VARS`
(`/usr/lib/python3/dist-packages/ansible/plugins/action/include_vars.py:148-151`), landing
in `_vars_cache` (manager.py:401-403, **above** play vars and vars_files).
`set_fact` uses EPHEMERAL_FACT (manager.py:404-405). The layer enum and the
"bare `ansible_facts`" back-compat path:

- `VariableLayer` enum: `_task.py:705-718` (CACHEABLE_FACT, INCLUDE_VARS, EPHEMERAL_FACT,
  REGISTER_VARS — order defines application order).
- **Compfuzor's `include_defaults` returns bare `result["ansible_facts"]`**
  ([include_defaults.py:74](/library/action_plugins/include_defaults.py)) and never calls
  `register_host_variables`. On 2.21 that means the executor stuffs it into
  **CACHEABLE_FACT** (`task_executor.py:556-558`), which the strategy routes to
  `set_host_facts` — the **persistent** fact cache
  (`/usr/lib/python3/dist-packages/ansible/plugins/strategy/__init__.py:662-684`;
  `manager.py:570-593` writes through to the cache plugin). Pre-2.21 this returned into the
  nonpersistent (ephemeral) layer. Net effect of the upgrade:
  - include_defaults output now sits **below** play vars and vars_files
    (manager.py:301-318 vs 320-360) instead of above them. The `k not in task_vars` filter
    makes this mostly unobservable (playbook-set keys are never returned anyway), so this
    is a silent semantic migration, not a break.
  - With a persistent fact-cache plugin configured (jsonfile/redis), compfuzor "defaults"
    would be written to the cache store and survive `--flush-cache`-less reruns. Latent
    footgun; today's memory cache makes it run-scoped.

### Is there any stock "play-level defaults everything beats"?

Reading get_vars end-to-end: **role defaults are the only stock layer below everything**
(manager.py:215-218). The neighboring candidates:

- `VARIABLE_PRECEDENCE` config only reorders inventory group-var entries
  (manager.py:114-115 `_ALLOWED`; `config/base.yml` `VARIABLE_PRECEDENCE` description:
  "Allows to change the group variable precedence merge order"). There is no knob to demote
  vars_files below play vars.
- **Vars plugins** (playbook-adjacent stage) load from `basedirs` at
  `all/groups_plugins_play` precedence (manager.py:250-252, 258-299;
  `/usr/lib/python3/dist-packages/ansible/vars/plugins.py:29-49,51-76`) — below play vars,
  above role defaults. This is a sanctioned extension point (it is how group_vars-style
  plugins work), runs pre-task per host, and needs no filtering: layering *is* the
  defaults semantics.
- Inventory `all` group vars sit below play vars too, but belong to inventory, not playbook.

There is no play keyword for defaults. The feeling of "fighting ansible's inner core" comes
from wanting a layer the play schema does not offer; the supported escape hatches are role
defaults and vars plugins.

## Compfuzor mechanism audit

### `library/action_plugins/include_defaults.py`

Fork of stock include_vars; key move at lines 69-73: `if k not in task_vars` — only UNDEFINED
(as of the task-time snapshot) keys are returned, tagged `TrustedAsTemplate` via
`_tag_strings_recursive` (lines 30-38), which mirrors core's vars_files trust treatment.

- The filter runs against the live flattened `task_vars` snapshot (play vars, vars_files,
  inventory, facts, prior set_fact/include layers are all in it). Membership on the plain
  snapshot dict does not force template resolution, so the filter itself cannot trip the
  cmdline failure.
- Play vars "win" twice over: they are in the snapshot (filtered out) *and* they sit above
  the fact layer the results land in on 2.21.
- First-writer-wins between successive include_defaults loads: because earlier loads'
  results are already in task_vars, later loads return those keys filtered. This is what
  makes the USERMODE ordering work — `common.user.yaml` loads first
  ([vars_base.tasks:3-17](/tasks/compfuzor/vars_base.tasks)) and common.yaml cannot clobber
  its overrides. Note the filter, not the layer, provides this: in the fact cache,
  `host_cache |= facts` (manager.py:590) would otherwise replace same-named keys on a
  second load.
- Edge cases:
  - Facts gathered earlier / keys set by prior tasks: any same-named key visible in the
    snapshot blocks the default. common.yaml's uppercase custom vocabulary makes
    collisions unlikely, but the semantics are "first writer anywhere wins", not "playbook
    wins".
  - Second loads are no-ops (see above); the loop at
    [vars_base.tasks:116-121](/tasks/compfuzor/vars_base.tasks) reloading `common.yaml`
    ahead of `vars/types/<type>.yaml` is therefore a no-op for every key common.yaml
    already set — only the type file contributes. The repeated common.yaml entry looks
    vestigial.
  - `--check`: the action is a local read-only loader; it still runs. Tags: it only runs
    where its task is reached (production gates it with `tags: ['vars','always']` in
    `tasks/compfuzor.includes`).
  - 2.21 layer placement: see the CACHEABLE_FACT surprise above.

### `library/lookup_plugins/playbook_identity.py`

Resolves provenance with explicit `COMPFUZOR_PLAYBOOK_PATH` → ansible CLI args → legacy
`/proc/self/cmdline`, retaining candidates and confidence (lines 51-63). common.yaml
predates it and still uses the raw cmdline hack.

- **Circularity**: `resolve_playbook_identity` *requires* resolved NAME (lines 44-49), and
  common.yaml's NAME requires TYPE. Migrating TYPE/INSTANCE_CMDLINE to this lookup as-is is
  impossible; it needs a new mode that derives type/instance *from the playbook basename*
  (identity derivation, not provenance reporting), with NAME fed in or ignored.
- **Does it fix the test failure class? No.** Test entrypoints are `render.pb` — no
  two-segment suffix to parse, from any source. And vars_files would still shadow the play
  var. What it *would* fix: wrapper/renamed-invocation fragility in production, and it
  gives tests a sanctioned pin (`COMPFUZOR_PLAYBOOK_PATH=...` instead of `-e`).
- Blast radius of a derivation mode: swap [common.yaml:4-5](/vars/common.yaml); keep
  INSTANCE logic (line 6) unchanged; `vars_base.tasks`'s separate `typeDetect` (line 95)
  would stay until separately consolidated.

### `tasks/compfuzor/vars_base.tasks`

Load order: common.user.yaml (USERMODE only) → common.yaml (lines 15-17) → shell probes →
`set_fact` identity layer (lines 59-114) → second loop common.yaml + vars/types/<type>.yaml
(lines 116-121). The set_fact layer already implements the lazy-default pattern with
task-local helper vars: `NAME: "{{name_}}"`, `TYPE: "{{TYPE|default(name_)}}"`,
`DIR: "{{prefix}}/{{name_}}"` (lines 86-89), where `name_`/`prefix`/`typeDetect` are vars
local to the task (lines 95-114) — precisely so `|default()` chains can see both the user
value and the derived value under different names. Lines 95-97 re-derive the class suffix
from `/proc/self/cmdline` in a *second*, slightly different regex (`^.*\.(.*)\.pb$` last
suffix) than `ansible_cmdline`'s two-segment pattern — two parallel cmdline parsers with
different failure envelopes (e.g. `adt.pb`: common.yaml yields `{}`; typeDetect yields the
unmatched original string).

Semantics note that surfaced during the audit and is worth confirming as intended
vocabulary: common.yaml's `TYPE` means the *first* filename segment (the deployment name,
e.g. `amp` → `/opt/amp-main`), while vars_base's lowercase `type` means the *class* suffix
(opt/srv/src → `vars/types/<class>.yaml` → DIR base). Same word, two meanings, two parsers.

### Integration test inventory

Stock `vars_files:` + common.yaml users and how they survive:

- `-e` workaround (robust): rust_bins (TYPE+NAME), links (TYPE+NAME),
  systemd_links, apt_deb822, archlane, kernel_bins, config_command, config_contexts,
  config_context_toolkit, container_profile, status_proc, zim_consumer — all pass extra
  vars that outrank the vars_files layer.
- Play var only, no `-e` (fragile — pass by luck): orchestrator_identity
  (lines 25-28), status_reporter_args (26-28), config_graph (57-59). They declare
  `TYPE:` as a play var under vars_files, which loses; they survive solely because nothing
  in their task graph forces TYPE materialization (2.21 laziness). One
  `{{TYPE}}`-embedding subsystem away from the same failure.
- Avoid common.yaml entirely: build_mise, bin_tombstones (pure play vars; bin_tombstones
  even runs merge_subsys safely because SUBSYSTEM/BINS live only in play vars).

Why rust_bins tripped and others didn't: the rust contrib BINS embed `{{ TYPE }}`
([common.yaml:466](/vars/common.yaml)); merge_subsys's exit render
([merge_subsys.py:328](/library/lookup_plugins/merge_subsys.py)) is a top-level template
that finalizes nested leaves; TYPE was the shadowed cmdline template; `render.pb` parses to
`{}`; `.type` fails. Tests whose artifacts never embed `{{TYPE}}` (or that pin it via `-e`)
never force the chain.

## Option matrix

| Option | Fixes | Leaves broken | Fighting core? | Cost |
|---|---|---|---|---|
| **A. standardize tests on include_defaults (shared helper)** | The entire failure class: include_defaults only fills UNDEFINED keys, play vars stay authoritative, no vars_files involved. One blessed render helper ends the three accidental test patterns. | Production cmdline fragility; the dual identity mechanisms; the vestigial second common.yaml load. | No — task-time snapshot semantics are the stable action-plugin contract. | Low: one tasks snippet (or python builder) + migrate ~15 test files. |
| **B. migrate identity to playbook_identity** | Wrapper/invocation robustness in production; tests gain `COMPFUZOR_PLAYBOOK_PATH` as a sanctioned pin. | Does **not** fix the incident class (`render.pb` has no identity to parse; vars_files still shadows play vars). Needs a new derivation mode to break the NAME↔TYPE circularity. | No. | Medium: new lookup mode + 2-line common.yaml swap; orthogonal track. |
| **C1. extend include_defaults to `VariableLayer.INCLUDE_VARS`** | Stops riding the 2.21 bare-ansible_facts back-compat shim (task_executor.py:556-558); makes the layer intent explicit and ephemeral again (pre-2.21 semantics: results above play vars, run-scoped). | Same as A's leftovers. The raised layer is masked by the `k not in task_vars` filter for playbook-set keys, but is a semantic change to document. | No — `register_host_variables` is marked public API (`_task.py:705-718` CAUTION note). | Low: two lines mirroring stock include_vars.py:148-151. |
| **C2. vars plugin loading common.yaml** | True "defaults lose to everything stock" placement (below play vars, above role defaults) with zero filtering; runs pre-task; sanctioned extension point. | No task context (identity must come from CLI args/env, which pushes toward B anyway); per-host invocation; needs ansible.cfg enablement; tests must still drop vars_files. | No — this is exactly what vars plugins are for. | Medium-high: new plugin + bootstrap rework. |
| **C3. role-defaults-shaped load** | The one stock below-everything layer (manager.py:215-218). | Structurally invasive: flat `.pb` collection would need a `roles:` entry per playbook (import_role scoping of defaults is murky); vars_files still outranks role defaults, so tests switch loaders regardless; silently reorders vs inventory vars. A distortion of the flat-playbook shape. | Not fighting, but leaning on easily-misread role semantics. | High. |
| **D. restructure common.yaml to lazy `user \| default(derived)` chains** | Precedence stops mattering *within the include_defaults flow* (it already doesn't); matches the pattern vars_base's set_fact layer already uses. | Self-reference problem: `TYPE: "{{ TYPE\|default(x) }}"` in one vars dict resolves to itself; the pattern only works at a boundary with differently-named helpers (as in vars_base). Does nothing for the vars_files shadowing — the play var stays unreachable. Large churn across a 1330-line common.yaml consumer surface. | No. | High. |
| **E. document the convention only** | Zero code. | Leaves the fragile set (orchestrator_identity, status_reporter_args, config_graph) as standing landmines; next `{{TYPE}}`-embedding subsystem in a vars_files test fails again. | — | Zero now, recurring later. |

### Recommendation

**A + C1, with B as a separate follow-up track.**

1. Adopt a shared test-render helper that loads `vars/common.yaml` through
   `include_defaults` (a tiny tasks snippet invoked first, or a python-side playbook
   builder) and migrate the vars_files tests to it. This is the only option that actually
   eliminates the failure *class* rather than its symptoms.
2. In the same motion, pin include_defaults to `VariableLayer.INCLUDE_VARS` (+ an empty
   CACHEABLE_FACT registration, mirroring stock include_vars) so the plugin stops depending
   on 2.21's legacy `ansible_facts` shim and stops writing "defaults" into the persistent
   fact-cache layer.
3. Treat B (playbook_identity derivation mode replacing `/proc/self/cmdline` in
   common.yaml:4-5 and eventually vars_base's `typeDetect`) as robustness work with its own
   wave — it is valuable but orthogonal to the precedence question, and it cannot fix tests
   that keep using stock `vars_files`.
4. Reject C3 as a distortion; decline D as a large churn that doesn't address shadowing;
   E alone is not acceptable given the fragile test set.

The direct answer to the operator's concern: no new action is needed to make common.yaml
lose to play vars — **stock `vars_files:` is the one doing the outranking**, and it outranks
play vars for *any* file. The custom loader is not fighting core; it is compensating for
using vars_files where a defaults loader belongs. Production already loads common.yaml the
right way; only the test harness was reaching for the stock keyword.

## Open questions for the operator

1. **include_defaults layer intent**: pin INCLUDE_VARS (ephemeral, above play vars —
   pre-2.21 behavior) as C1 proposes, or keep bare `ansible_facts` (now persistent-cache
   bound on 2.21)? If a persistent fact-cache plugin is ever in compfuzor's future, C1 is
   required, not optional.
2. **Test render fidelity**: should the shared helper run the full
   `tasks/compfuzor.includes` bootstrap (closer to production, slower) or a minimal
   include_defaults + common.user.yaml pair (fast, sufficient for these tests)?
3. **Vestigial load**: is the second `vars/common.yaml` entry in the
   vars_base.tasks:116-121 loop load-bearing for any skip path, or can it drop out of the
   assessment's future cleanup list?
4. **B scope**: should playbook_identity grow a basename→(type, instance) derivation mode
   so common.yaml can drop `/proc/self/cmdline`, and should tests pin identity via
   `COMPFUZOR_PLAYBOOK_PATH` instead of `-e`?
5. **Vocabulary**: confirm the dual meaning of TYPE (name segment in common.yaml) vs type
   (class segment in vars_base) is intended, or whether a rename/consolidation wave is
   warranted.

## Cross-references

- [`/vars/common.yaml`](/vars/common.yaml) — identity templates under assessment
  (lines 3-6) and the `{{ TYPE }}`-embedding rust bin leaf (line 466).
- [`/library/action_plugins/include_defaults.py`](/library/action_plugins/include_defaults.py)
  — the custom loader; `k not in task_vars` filter (69-73), bare `ansible_facts` return
  (74), manual TrustedAsTemplate tagging (30-38).
- [`/library/lookup_plugins/playbook_identity.py`](/library/lookup_plugins/playbook_identity.py)
  — provenance resolution and the NAME-requires-circularity constraint (44-49).
- [`/library/lookup_plugins/merge_subsys.py`](/library/lookup_plugins/merge_subsys.py) —
  raw-copy discipline (232) and the forcing top-level exit render (328).
- [`/library/lookup_plugins/subsys.py`](/library/lookup_plugins/subsys.py) —
  `_template_value` failure swallowing (108-115) that keeps intermediate steps non-fatal.
- [`/library/filter_plugins/cmdline.py`](/library/filter_plugins/cmdline.py) — the
  `ansible_cmdline` parser whose `{}` return triggers the Marker.
- [`/library/filter_plugins/template_data.py`](/library/filter_plugins/template_data.py) —
  `raw_copy_template_data` / `dict_get_raw` primitives for lazy-safe access.
- [`/tasks/compfuzor/vars_base.tasks`](/tasks/compfuzor/vars_base.tasks) — production load
  order, the set_fact identity layer (59-114), and the second-loop reload (116-121).
- [`/tasks/compfuzor.includes`](/tasks/compfuzor.includes) — the bootstrap that every
  production playbook routes through (vars_base with `tags: always`).
- [`/tasks/compfuzor/sub_attribution.tasks`](/tasks/compfuzor/sub_attribution.tasks) — the
  playbook_identity consumer.
- [`/tests/integration/rust_bins.test.py`](/tests/integration/rust_bins.test.py) — the
  incident test; vars_files+play-var TYPE (34-37) and the `-e` workaround (59-62).
- [`/tests/integration/links.test.py`](/tests/integration/links.test.py) — prior adopter of
  the `-e` workaround (93-94).
- [`/tests/integration/orchestrator_identity.test.py`](/tests/integration/orchestrator_identity.test.py),
  [`/tests/integration/status_reporter_args.test.py`](/tests/integration/status_reporter_args.test.py),
  [`/tests/integration/config_graph.test.py`](/tests/integration/config_graph.test.py) — the
  fragile set: play-var TYPE under vars_files with no `-e`.
- [`/tests/integration/bin_tombstones.test.py`](/tests/integration/bin_tombstones.test.py)
  and [`/tests/integration/build_mise.test.py`](/tests/integration/build_mise.test.py) —
  the avoiders: pure play vars, no common.yaml load.
