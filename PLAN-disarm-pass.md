# Automatic subsystem/action disarm status

Convention home: [`doc/subsys.md`](doc/subsys.md) § Automatic bin disarm.

## Goal

Every rendered shell BINS action can be disarmed at a broad concern and nested
action level without routine `bypass:` authoring. Metadata follows subsystem
contributions into same-name BINS merges, while compositor grouping remains an
independent concern.

## Implemented

- `merge_subsys` annotates active incoming BINS with `origin_subsystems` and
  `bypass_scopes` before `bins_generated` merging.
- Scope precedence is explicit `domain=` > subsystem record `domain` >
  subsystem ID. Origin is always the subsystem ID. The resolved domain is also
  passed through standard subsystem-state evaluation, so `<DOMAIN>_BYPASS`
  suppresses the incoming contribution.
- `bins_generated` concatenates both metadata lists in contribution order.
  [`resolve_bin_disarm`](/library/filter_plugins/bin_disarm.py) stable-dedupes
  them at render time.
- [`files/_bin`](/files/_bin) resolves policy once and emits broad `SCOPE` plus
  nested `SCOPE:ACTION` guards. Existing explicit `bypass` entries extend that
  policy; `bypass: false` disables outer guards and `helpers: false` remains the
  nuclear wrapper opt-out.
- Direct, unannotated `.sh` records fall back to `TYPE`, including the report
  label without inventing provenance. Pure generated compositors do not use
  that fallback. If a generated canonical compositor merges with an authored
  body, the body's guards are local: a skip suppresses that body but still runs
  `run_all`; a successful body completes before children run.
- Reports use the actual script filename, a derived or authored verb, and
  stable subsystem labels: `build-go.sh: build (go)`.
- Manual aggregators cover kernel leaf origins with broad `kernel`, generated
  systemd records, MCP, config's `CONFIG_KEY` domain, get-urls/status,
  Python console records, zim, NVIM, and the Go repo helper.
- NVIM keeps executable concatenation narrow (`generated` only; `early` and
  `run_all` remain later-wins) while concatenating both disarm metadata lists.
- The sourced systemd `install-unit.sh` record explicitly uses `bypass: false`.
- Systemd phase controls use `COMPFUZOR_SYSTEMD_LINK_BYPASS`,
  `COMPFUZOR_SYSTEMD_ENABLE_BYPASS`, and
  `COMPFUZOR_SYSTEMD_START_BYPASS`. The old `SYSTEMD_BYPASS_*` variables remain
  documented temporary soak aliases for already-generated artifacts.
- Nuclear `install-dropin.sh` retains `helpers: false` and enforces
  `COMPFUZOR_SYSTEMD_BYPASS` plus
  `COMPFUZOR_SYSTEMD_INSTALL_DROPIN_BYPASS` internally before its LINK phase.

## Deliberate boundaries

- `subsystem` still controls compositor grouping only. It is not provenance.
- Compositors do not aggregate child guard metadata.
- Canonical body/compositor collisions use only the canonical body's own
  metadata, explicit bypass, or TYPE fallback; child policy remains in children.
- `run_all`, `base_helpers`, and [`files/_helpers/env`](/files/_helpers/env) are
  unchanged.
- Public `bypass` remains an ordinary later-defined BINS field rather than a
  concat field. This preserves authored phase guards such as `BUILD` and
  `LINK:SERVICE` while allowing later records to replace earlier policy.
- Deprecated merge files and tests remain unchanged for soak.

## Remaining rollout

- Direct `.sh` records are covered by TYPE fallback. As sourced or library
  scripts are discovered, mark them `bypass: false` rather than wrapping a
  sourced body whose guard exits the caller.
- Remove `SYSTEMD_BYPASS_*` aliases only after concrete generated artifacts and
  operators have completed their soak period.
- Opportunistically add manual `annotate_bins` calls where a future aggregator
  has a more meaningful domain than TYPE; routine `merge_subsys` callers need
  no authored scope.
- Keep the full tests and representative playbook syntax checks in the release
  verification loop so metadata, rendering, and compositor behavior cannot
  drift independently.

## Verification contract

The current suite covers canonicalization, scope precedence, lazy values,
same-name metadata concatenation, later-wins `bypass`, compositor isolation,
canonical-body local skips with continuing children, real-Ansible rendering and
execution, fallback labels, false/nuclear opt-outs, unit guards, explicit macro
labels, behavioral systemd broad/nested/canonical/alias checks, kernel
hierarchy, and the lazy keyed-BINS/NVIM narrow-executable acceptance.
