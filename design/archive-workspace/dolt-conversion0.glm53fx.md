---
type: Report
title: Dolt deployment converted from archive symlink to a local jj workspace
description: The /usr/local/src/dolt-git/repo deployment was converted from a symlink into the shared dolthub/dolt archive to a dedicated jj/Git workspace backed by that archive, via the dolt.src.pb playbook, behind the assessment's CIFS-phantom preflight; run 1 hit a transient stat failure at the deploy guard, run 2 completed the conversion, and run 3 verified the fixed build lane (dolt's Go module lives in repo/go, which the generic go subsystem cannot express).
resource: /design/archive-workspace/dolt-conversion0.glm53fx.md
tags: [compfuzor, archive, dolt, jj, git, cifs, workspace, deploy, build, go-subsystem, build-lane]
status: draft
generated: { by: model:glm5.3-flash-max, at: 2026-10-16 }
verified: { by: model:glm5.3-flash-max, at: 2026-10-16 }
sources:
  - id: commissioning
    resource: opencode://ses_eba42c532ffeGDFn343ysNvjcd
    title: Commissioning session — dolt workspace conversion
  - id: authoring-session
    resource: opencode://ses_eba18319cffehzpQKhpPZLkvUr
    title: Executed the dolt workspace conversion, diagnosed the build-lane failures, fixed dolt.src.pb; authoring session for this document
  - id: prior-assessment
    resource: /design/archive-workspace/dolt-archive-state0.glm53fx.md
    title: Forensic assessment of the dolt archive dirty working-copy state (whose preflight this conversion ran)
  - id: playbook-log
    resource: /tmp/opencode/dolt-convert.log
    title: ansible-playbook dolt.src.pb output — run 1 failed at the deploy guard, run 2 failed in the build lane, run 3 completed (failed=0)
  - id: archive-repo
    resource: /mnt/bitblaster/archive/dolthub/dolt
    title: dolthub/dolt archive repository (read-only queries enumerated in Preflight and Verification)
  - id: deployment
    resource: /usr/local/src/dolt-git
    title: The converted dolt-git deployment (workspace, bins, env)
  - id: archive-readme
    resource: /archive/README.md
    title: Archive toolkit operator guide — Compfuzor integration semantics
  - id: deploy-source
    resource: /archive/src/repository/deploy.ts
    title: Deploy lane source — the jj-colocated archive guard that transiently misfired in run 1
  - id: playbook
    resource: /dolt.src.pb
    title: The dolt source deployment playbook (as fixed — build-dolt.sh from repo/go, TOOL_VERSIONS go)
  - id: go-contrib
    resource: /vars/common.yaml
    title: compfuzor SUBSYSTEM registry — go/rust/nodejs/bun/bazel/cmake/make contribs compared in the assessment
---

# Dolt deployment converted from archive symlink to a local jj workspace

## Result

**Converted and verified.** `/usr/local/src/dolt-git/repo` is now a dedicated
jj/Git workspace backed by the shared archive repository store, checked out at
origin `main` (`62b132d2`, "Merge pull request #11899" — upstream had advanced
since July and the deploy lane's fetch moved the repo-level bookmarks), and
`/usr/local/bin/dolt` resolves to a freshly built `repo/go/dolt`
(`dolt version` → 2.4.2). The playbook completed end-to-end with `failed=0` on
the third run.

Three runs were needed:

1. **Run 1** — failed harmlessly at the deploy lane's first guard on a one-off
   transient stat failure over CIFS; no mutation occurred; rerun unchanged.
2. **Run 2** — the entire deploy lane succeeded (symlink replaced, workspace
   created, checkout advanced to `main@origin`); the generic `go` subsystem
   build then failed for a structural reason: dolt's Go module lives in
   `repo/go`, which the go contrib's fixed `basedir: repo` layout cannot
   express. Fixed in `dolt.src.pb` (committed as
   `yxsqtmkm` "build: dolt module lives in repo/go; build it from the module
   root").
3. **Run 3** — clean end-to-end pass; all verification checks below observed.

## Preflight evidence

All checks were run immediately before each playbook invocation, per
[the assessment's guard](/design/archive-workspace/dolt-archive-state0.glm53fx.md#implications-for-the-pending-dolt-workspace-conversion).
All three runs observed identical, clean values:

| Check | Command | Observed |
|---|---|---|
| Dirty entries | `git -C /mnt/bitblaster/archive/dolthub/dolt status --porcelain \| wc -l` | **0** (every run) |
| Non-exec mode | `stat -c '%a' …/dolt/README.md` | **664** |
| Tracked script modes | `stat -c '%a' …/dolt/.github/scripts/fuzzer/run-fuzzer.sh` and `…/dolt/go/Godeps/update.sh` (first tracked script found under `go/`) | **775** / **775** |
| jj working copy | `jj --ignore-working-copy -R /mnt/bitblaster/archive/dolthub/dolt status` | "The working copy has no changes." `@` = `zmlxpmlp a36a0d57` (empty), parent `d0e0a56a` |

Pre-conversion deployment state (as the commissioning brief described):
`/usr/local/src/dolt-git/repo` was a symlink →
`/home/rektide/archive/dolthub/dolt` → the archive; `/usr/local/bin/dolt` →
`/usr/local/src/dolt-git/repo/go/dolt` was **dangling** (the stale 156 MB
archive binary had been deleted earlier; `test -e` → no such file), and both
`dolt sql-server` beads processes were stopped.

## Conversion + build outcome

### Run 1 — transient failure at the deploy guard, no mutation

Run 1 (18:11 UTC) failed in 1.5 s at the deploy lane's first guard with
`/home/rektide/archive/dolthub/dolt is not a jj-colocated archive; prepare it
separately` ([deploy.ts:96](/archive/src/repository/deploy.ts)). The guard
accepts the archive when it exists as a directory containing `.jj/` and
`.git/`, following a symlinked final component (`archiveEntryAt`), and all of
those stat correctly — verified before and after the run, including by
re-running the same `lstat`/`stat` sequence under Node. The error can only
fire when one of those stats transiently fails with `ENOENT` (a failed `stat`
of the archive falls back to the symlink entry, which is not a directory),
consistent with a one-off hiccup on the loaded CIFS server (the wrangler
conversion's I/O was in flight against the same mount at the time). The log
shows the guard fired before any fetch or mutation: the workspace symlink was
intact afterwards, so nothing was half-done. Rerunning unchanged was argued as
safe.

### Run 2 — conversion succeeded; the build lane failed on a real defect

Run 2 (18:15–18:17 UTC) completed the entire deploy lane
([log](/tmp/opencode/dolt-convert.log), "Compfuzor: collect jj archive
notices"):

- replaced archive symlink `/usr/local/src/dolt-git/repo` (→
  `/home/rektide/archive/dolthub/dolt`) with a dedicated jj/Git workspace;
- created jj workspace `/usr/local/src/dolt-git/repo` backed by
  `/home/rektide/archive/dolthub/dolt`;
- merged local checkout with `main@origin`.

The fetch also advanced the repo-level bookmarks: upstream dolt had moved
since the July pull, so `main` = `origin/main` = `62b132d2` in the shared
repository now. The archive's own worktree intentionally stays checked out at
its recorded `d0e0a56a` state — `@` unchanged, worktree clean. (Bookmarks are
repo-level in a colocated jj/Git setup, which is why the archive's parent
commit no longer carries the `main` label in `jj status`.)

The run then failed in the build lane: the generic `go` subsystem bin
`build-go.sh` ran `go build -o dolt ./...` from `/usr/local/src/dolt-git/repo`
and died immediately with
`pattern ./...: directory prefix . does not contain main module or its selected
dependencies`. Full analysis in
[the assessment](#assessment-what-got-in-the-way-in-the-build-lane); in brief,
three stacked causes:

1. **`GO_TARGET` never reached the bin** — the opencode harness exports a
   deployment-shaped env (`DIR=/usr/local/src/opencode-git`, …) that leaks
   into playbook bins, so `build-go.sh` sourced the wrong deployment's
   `env.export` (no `GO_TARGET`) and fell back to `./...`.
2. **Even with correct env the command is wrong for dolt** — the go contrib
   hardcodes `basedir: repo`; dolt's `go.mod` is in `repo/go`; a playbook
   cannot override it (the `bins_generated` fold lets the contrib replace
   playbook fields).
3. **`install-go.sh` would mislink** even on success (`repo/dolt` instead of
   the linked `repo/go/dolt`).

**Fix (dolt.src.pb, committed separately before the rerun):** retire the go
subsystem for this deployment (its gate is the `GO` var) and declare dolt's
own build bin, following the zephyr (`basedir: repo/zephyr`) and skyboard
(`basedir: repo/cli`) playbook patterns:

- `build-dolt.sh`: `basedir: repo/go`, `run: True`,
  `go build -o dolt ./cmd/dolt` — self-contained (no env dependence), immune
  to the harness `DIR` leak; the binary lands at `repo/go/dolt` where the
  existing `/usr/local/bin/dolt` link points.
- `TOOL_VERSIONS: {go: True}` at playbook level (vicinae precedent) so the
  mise go pin survives the go subsystem's retirement (run 3's `build-mise.sh`
  wrote the identical pin, base64 `Z28gMQo=` = `go 1`).
- Removed the stale legacy `build.sh`/`install.sh` BINS entries: dolt has no
  `go/build.sh` or `go/install.sh`; those entries had been silently degrading
  into family-trampoline metadata (see assessment).

`ansible-playbook dolt.src.pb --syntax-check` passed before the rerun.

### Run 3 — clean pass

Run 3 (18:36–18:39 UTC) exited 0, recap `ok=98 changed=4 unreachable=0
failed=0 skipped=184`. The deploy lane reported `ok` (workspace already
present — the normal subsequent-deployment path per
[the archive guide](/archive/README.md#compfuzor-integration)), `build-mise.sh`
maintained the pin/link, and `build-dolt.sh` (`basedir: repo/go`) performed
the build.

## Verification checklist

| Check | Command | Observed |
|---|---|---|
| Playbook outcome | run 3 exit + `PLAY RECAP` | **exit 0**; `failed=0` |
| Workspace is a real dir | `ls -lad /usr/local/src/dolt-git/repo` | `drwx------` directory (symlink replaced) |
| jj pointer into archive | `cat …/repo/.jj/repo` | `../../../../../../mnt/bitblaster/archive/dolthub/dolt/.jj/repo` (relative) |
| Git pointer into archive | `cat …/repo/.git` | `gitdir: ../../../../../mnt/bitblaster/archive/dolthub/dolt/.git/worktrees/repo` (relative) |
| Workspace at origin main | `git -C /usr/local/src/dolt-git/repo log --oneline -1` | `62b132d20e Merge pull request #11899 from dolthub/aaron/comment-fixup` |
| Build result | `ls -la …/repo/go/dolt` | `-rwx------ … 166656312 Oct 16 14:39` (fresh, 166 MB) |
| Global link resolves | `readlink -f /usr/local/bin/dolt` | `/usr/local/src/dolt-git/repo/go/dolt` (no longer dangling) |
| Binary runs | `dolt version` | `dolt version 2.4.2` |
| jj workspaces | `jj --ignore-working-copy -R /mnt/bitblaster/archive/dolthub/dolt workspace list` | `default` (archive) + `compfuzor-dolt-git-61f4a96dfbac: …/usr/local/src/dolt-git/repo` |
| Archive untouched | archive `git status --porcelain \| wc -l`; `jj --ignore-working-copy … status` | **0**; "The working copy has no changes." `@` unchanged (`zmlxpmlp a36a0d57`) |
| No exec from the mount | `for f in /proc/[0-9]*/exe; do readlink …; done \| rg bitblaster` | empty |

## Assessment — what got in the way in the build lane

This section records, with evidence, what the dolt conversion revealed about
compfuzor's build-lane modeling, for the follow-up design effort on build-lane
modularization.

### The GO:True lane failure was three stacked defects, only one of them dolt's

The immediate error (`pattern ./...: directory prefix . does not contain main
module`) came from running `go build ./...` in a directory that is not a Go
module. Peeling it:

1. **Wrong env file sourced.** Materialized bins open with an env helper:
   `[ -z "$DIR" ] && export DIR="…"; … source envdefault "$DIR/env.export"`.
   Two fragile choices compose here. The helper defers to an **inherited**
   `$DIR`, and `envdefault` applies only variables **not already present** in
   the invoking shell (that is its contract — environment wins over the file).
   The opencode harness exports a complete deployment-shaped environment for
   its own compfuzor deployment (`DIR=/usr/local/src/opencode-git`,
   `NAME=opencode-git`, `TYPE=opencode`), which ansible's local connection
   passes to the bins. `build-go.sh` therefore sourced
   `/usr/local/src/opencode-git/env.export` — traced directly:
   `+ source /usr/local/bin/envdefault /usr/local/src/opencode-git/env.export`
   — which has no `GO_TARGET`, so `${GO_TARGET:-./...}` fell back. Silent,
   because envdefault exits 0 after sourcing the wrong file. This is **not
   GO-specific**: every materialized bin has this helper, and any bin whose
   behavior depends on env vars was exposed during harness-driven runs.
   Operator shells (no inherited `DIR`) work correctly.
2. **Wrong working directory, unfixable from the playbook.** The go contrib
   hardcodes `basedir: repo` for both its bins
   ([vars/common.yaml](/vars/common.yaml), `go:` block), but dolt's module is
   `repo/go` (`module github.com/dolthub/dolt/go`). I verified the merge
   machinery blocks a playbook-level repair: `gen_bins.tasks` folds playbook
   `BINS` with contrib bins via `merge_list(preset='bins_generated')`, a
   `keyed_fold` on `name` where **later layers replace ordinary fields** —
   the contrib is the later layer, so a playbook's `basedir: repo/go` for
   `name: build-go.sh` loses; and `generated` is a **concat** field, so the
   playbook's text runs *before* the contrib's failing line with no way to
   prevent it (short of an `exit 0` trap, which reads as sabotage). The only
   clean playbook-level move was retiring the subsystem (`GO: False` — with
   no explicit `requested`, the subsystem's gate is the uppercase var, per
   `library/lookup_plugins/subsys.py`) and declaring dolt's own bin.
3. **The install half would have corrupted the deployment on success.** With
   `GO_BIN` unset, `install-go.sh` links `$(pwd)/${INSTALL_BIN:-$TYPE}` from
   `basedir: repo` — `repo/dolt`, not the `repo/go/dolt` path that
   `/usr/local/bin/dolt` (and the pre-conversion deployment) actually used.
   A successful generic build would still have produced a wrong or dangling
   global link.

### dolt's own legacy BINS were a silent no-op that made things look modeled

`dolt.src.pb` carried `BINS: [build.sh, install.sh]` with `basedir: repo/go`
and no `run`/`content`/`exec` — evidently a hand-rolled attempt to build from
`repo/go`, predating the go contrib. dolt has no `go/build.sh` or
`go/install.sh`, and entries without `run`/`args` are not auto-executed, so
these **never ran anything**. They did not even fail loudly: the composer
folded them into the generated family trampolines by name, and they surfaced
in the run loop only as `skipping` items — e.g. run 2's log:
`{'name': 'build.sh', 'action': 'build', 'run_all': ['build-mise.sh',
'build-go.sh'], 'basedir': 'repo/go', 'generated_by': 'gen_bins'}`. Note the
fold nuance: the family record **inherited `basedir: repo/go` from the
playbook entry** (the composer does not set `basedir`, so the first layer's
value survived) while the generic `build-go.sh` it aggregates kept
`basedir: repo` — two different working directories inside one deployment's
build flow, with nothing flagging the conflict. Removing the dead entries was
part of the fix.

### The GO lane is the least-modeled build lane

Comparing the contribs in
[vars/common.yaml](/vars/common.yaml):

| Lane | Model | Handles non-root module/project dirs? |
|---|---|---|
| cmake | **structured build rows** (`_cmake_builds`: `name`, `source_dir`, `build_dir`, `generator`, `args`, `build_type`, `install`) | yes — `source_dir`/`build_dir` per row |
| rust | **manifest discovery** (walks for `Cargo.toml`, `cargo install --path $(dirname …)`) plus rich env knobs (`RUST_BIN`, `RUST_PKG`, `RUST_FEATURES`, `RUST_PROFILE`, `RUST_ALL`, `RUST_LOCKED`, `RUST_COPY`) | yes — discovery |
| nodejs | **project-manifest-driven** (`pnpm` scripts via `NODEJS_BUILD_SCRIPTS`/`NODEJS_BUILD_COMMANDS`) | n/a (root `package.json` convention), but behavior is delegated to the project |
| bun | env knob (`BUN_BUILD_SCRIPTS`) | no, same root convention |
| bazel | target knob (`BAZEL_TARGET`, `BAZEL_INSTALL_TARGETS`) | no (`basedir: repo` fixed) |
| **go** | **two string knobs** (`GO_TARGET`, `GO_BIN`) + fixed `basedir: repo`; `install-go.sh` assumes the binary was dropped at `$(pwd)/$TYPE` | **no** — no module-dir concept, no discovery, no install-target model |

Go is the odd one out: cmake got build rows, rust got discovery, nodejs/bun
delegate to the project — go got two substitution variables and a hardcoded
cwd. Monorepo-style Go projects (dolt, and many others) put the module in a
subdirectory, so `GO_TARGET=./cmd/dolt` is uninterpretable without a module
dir the playbook cannot express. The install half compounds it: rather than
an explicit output path, it guesses `$(pwd)/$TYPE`.

### Hypothesis: what a more modular build-lane design should fix first

1. **Make the build a declared, data-shaped capability, not a bin to fight.**
   The cmake lane's `_cmake_builds` rows are the right shape: a `go` lane
   wants `GO_BUILDS` rows (`module_dir`, `target`, `output`, `install_to`) —
   or, more uniformly, a shared build-row schema that every compiled-language
   lane speaks, so playbooks declare intent (`module in repo/go, binary to
   repo/go/dolt, link to GLOBAL_BINS_DIR`) instead of pre-baking shell into
   `generated:` blobs. My `build-dolt.sh` fix is the playbook-side escape
   hatch working as designed; the escape hatch should not be the only
   supported path for a whole class of repos.
2. **Fix the fold direction for playbook-vs-contrib.** A declaring playbook
   should win on ordinary fields for a same-named bin (or contribs should be
   gated entirely behind "no explicit user bin for this concern"). Today the
   layering silently prefers the generic bin's `basedir`/`run` over the
   playbook's, which turns playbook attempts to specialize into dead
   metadata (exactly what dolt's legacy `build.sh`/`install.sh` became).
3. **Pin the deployment environment inside materialized bins.** The bin knows
   its deployment absolutely (`cd /usr/local/src/dolt-git/…` is baked in) yet
   still trusts inherited `$DIR` for the env file. Bins should resolve their
   env relative to their own known deployment root (e.g. derive `DIR` from
   the script's location) rather than accepting a parent process's
   deployment-shaped variables. The harness's leaked `DIR`/`NAME`/`TYPE` is
   the standing hazard that made cause 1 invisible in the playbook's own
   abstractions.
4. **Surface env-sourcing decisions.** `envdefault`'s only-unset semantics
   plus a wrong-but-existing file made the failure silent. A bin that sources
   an env file should announce which file it used (loud mode already exists
   via `V>2`, but the default is quiet) — the mismatch (`bin claims
   deployment X, sourced env of deployment Y`) is mechanically checkable.

## Open / handed off

- **In flight at wrap-up: nothing.** The third playbook run completed on its
  own (`exit: 0`, recap `failed=0`) moments after the operator's wrap-up
  direction, so no processes were left running and none were killed. The
  build had been observed executing as `build-dolt.sh` (PID 1820686) →
  `go build -o dolt ./cmd/dolt` (PID 1823729, go 1.26.5 via mise) before
  completing; log at `/tmp/opencode/dolt-convert.log` (run 3 overwrote the
  log; runs 1–2 excerpts are quoted in this report).
- **Services stay stopped.** No dolt sql-server, lact-git, or mk-wed was
  started; `dolt version` was the only binary invocation.
- **Archive cleanup deferred** (per commissioning brief): no rm/mv on
  `/mnt/bitblaster/**` beyond what the playbook's deploy lane itself did
  (which, on the archive side, was only the one-time `@` snapshot and the
  bookmark/fetch updates; the archive worktree still holds its pre-conversion
  checkout at `d0e0a56a` and remains clean).
- **The harness env leak is unresolved** (assessment cause 1): bins invoked
  from opencode-driven shells source the wrong deployment's env whenever they
  depend on env vars. dolt's build is now immune (self-contained command),
  but this remains a general hazard for other deployments driven from agent
  sessions.
- **The generic GO lane remains as-is** for other deployments; only
  `dolt.src.pb` was changed. Follow-up design effort on build-lane
  modularization is the intended consumer of the assessment above.
- **Upstream moved**: the workspace checkout is now `62b132d2` (October
  upstream), not the July `d0e0a56a` the archive worktree still holds. The
  dolt binary therefore includes ~3 months of upstream changes relative to
  the previously deployed (March-built) binary.

## Cross-references

- [Dolt archive dirty-state assessment](/design/archive-workspace/dolt-archive-state0.glm53fx.md) —
  the forensic report whose conclusion ("clean now, convert behind the
  preflight") this conversion executed; its preflight is reproduced above and
  its phantom-window warning framed how run 1's guard failure was judged.
- [Archive toolkit operator guide](/archive/README.md#compfuzor-integration) —
  deploy's workspace-creation semantics: legacy final-component symlink
  replacement, the one-time archive `@` snapshot, subsequent-deployment
  refresh behavior, and the restore-link-on-failure safeguard (which run 1's
  early guard failure never reached).
- [Conversion research wave](/design/archive-workspace/conversion0.gpt6luna.md) —
  the original conversion design this deployment follows.
