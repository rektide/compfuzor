---
type: RuntimeVerification
title: Archive toolkit runtime & distribution boundary checks
description: Tested Node-version matrix, signal/subprocess lifecycle, and bundle freshness for the Effect CLI migration; findings and an upstream-only lifecycle proposal.
status: draft
generated: { by: model:glm53, at: 2026-09-28 }
verified: { by: model:glm53, at: 2026-09-28, note: all empirical claims below were executed against the local checkout; no production processes touched }
sources:
  - resource: /archive/src/cli/main.ts
    title: CLI runner wiring (Effect.runPromise, output buffering)
  - resource: /archive/src/repository/jj.ts
    title: jj adapter — effect/process spawner boundary and query-mode flags
  - resource: /script/repo-jj-archive.ts
    title: Ansible-facing launcher and its resolution order
  - resource: https://unpkg.com/@effect/platform-node-shared@4.0.0-rc.118/dist/NodeRuntime.js
    title: Upstream NodeRuntime.runMain — SIGINT/SIGTERM fiber interruption (installed rc118)
  - resource: https://unpkg.com/@effect/platform-node-shared@4.0.0-rc.118/dist/NodeChildProcessSpawner.js
    title: Upstream spawner — acquireRelease scope finalizer, process-group SIGTERM→SIGKILL
  - resource: https://nodejs.org/api/typescript.html
    title: Node.js type stripping (which versions run .ts directly)
---

# Situation

The archive toolkit CLI is now on exactly pinned `effect` / `@effect/platform-node`
`4.0.0-rc.118`; jj and git spawn through `effect/process`'s
`ChildProcessSpawner` (provided by `NodeServices.layer`), and [`main()`](/archive/src/cli/main.ts)
stays a plain `Promise` for launcher/bundle import-contract stability. `package.json`
advertises `engines: ^20.19.0 || ^22.18.0 || >=24.11.0`; the vite `pack` target is
`node20.19`; a committed single-file ESM bundle
([`archive/repo-jj-archive.mjs`](/archive/repo-jj-archive.mjs)) serves trees without
source or `node_modules`.

This round verifies, read-only, that the advertised distribution/runtime boundaries
actually hold: which Node versions can run which entry path, whether the upstream
Effect lifecycle cancels in-flight subprocesses on SIGINT/SIGTERM, and whether the
committed bundle matches the committed source. The bundle is known to lag the
latest jj/custody commits and will be finally rebuilt separately — that mismatch is
characterized here, not fixed. No source, bundle, or package files were changed.

Empirical method: a fake `jj` executable and a signal probe live in
`.test-agent/archive-runtime-checks/` (gitignored scratch; see its README). The fake
jj logs argv/PID, sleeps 30 s, exits 0 — long enough to observe whether the CLI's
`Effect` wrapper cancels the child when the parent is signaled. All CLI functional
tests ran against a local git+jj colocated fixture; no network, no production
processes. Environment: jj 0.45.1, git 2.55.0, Linux, Node via mise.

# Version matrix (tested)

| Entry path | 20.19.0 | 22.20.0 | 24.10.0 | 26.6.0 |
|---|---|---|---|---|
| Bundle `archive/repo-jj-archive.mjs` | ✅ version/help/health/legacy refresh | ✅ | ✅ | ✅ |
| Source `archive/src/repo-jj-archive.ts` | ❌ `ERR_UNKNOWN_FILE_EXTENSION` | ✅ | ✅ | ✅ |
| Launcher `script/repo-jj-archive.ts` | ❌ fails before any fallback | ✅ | ✅ | ✅ |

- `process.features.typescript` is `"strip"` on 22.20.0 / 24.10.0 / 26.6.0 and
  `undefined` on 20.19.0: Node 20.x has no type stripping at all (introduced
  experimentally in 22.6, default since 23.6, backported default to 22.18 — hence
  the engines range). 20.19's significance is `require(esm)` unflagging
  (`require_module: true`), which the pure-ESM bundle never needs.
- The source tree is erasure-safe TypeScript: a scan of `archive/src` and `script/`
  found no enums, namespaces, constructor parameter properties, or decorators, so
  flag-free stripping suffices everywhere it exists; `--experimental-transform-types`
  is never required.

# Findings

## F1 — the engines floor is the toolchain's, not Effect's

`effect` rc118 declares no engines; `@effect/platform-node` rc118 declares
`node >= 18.0.0`. The project range
`^20.19.0 || ^22.18.0 || >=24.11.0` is byte-identical to `vite-plus@0.3.1`'s
engines — it mirrors the build toolchain. Nothing upstream forces the 20.19 floor,
and nothing upstream forbids it either; the floor is a project commitment that
must be honored by the bundle alone (see F2).

## F2 — direct-TS and bundle are different support stories; the launcher's fallback is unreachable on Node 20

The honest distinction the engines range obscures:

- **Compiled bundle**: genuinely supports Node 20.19+ (verified on 20.19.0: version,
  help, health, full legacy refresh contract). This is the only artifact that makes
  `^20.19.0` true.
- **Source / launcher (direct TS)**: requires a type-stripping-default Node
  (22.18+, 23.6+, 24+). On 20.19.0 both fail with `ERR_UNKNOWN_FILE_EXTENSION`.

Two concrete consequences on Node 20 hosts:

1. The launcher is itself TypeScript, so on Node 20.x it dies before its own
   resolution logic runs — the documented "fall back to the bundle" path is
   unreachable there. Exit is 1.
2. The Ansible task defaults `COMPFUZOR_REPO_JJ_RUNNER` to
   [`script/repo-jj-archive.ts`](/tasks/compfuzor/repo_jj_archive.tasks); a Node 20
   controller fails unless the variable is overridden to the `.mjs` bundle.

Gap (not applied — read-only round): the launcher has no runtime capability probe,
and its file-existence fallback cannot help where the failure is the launcher
itself. If Node 20 support via launcher matters, the fix is distribution shape
(e.g. a JS launcher shim preferring source), not a version check inside the TS
file. Documenting the `COMPFUZOR_REPO_JJ_RUNNER` override as the Node 20 story is
the zero-code alternative.

## F3 — SIGINT/SIGTERM orphan in-flight subprocesses; two upstream pieces are needed, not one

Static reading of the installed rc118 (byte-identical to the canonical unpkg
sources cited above):

- [`Command.runWith`](https://unpkg.com/effect@4.0.0-rc.118/dist/cli/Command.js) is
  parse+execute only; it is not a runner. Signal responsibility belongs entirely to
  how the program is run.
- `main.ts` runs the program with `Effect.runPromise`, which installs **no** signal
  handlers — a SIGINT/SIGTERM kills the Node process by default, never
  interrupting the fiber.
- Upstream `NodeRuntime.runMain` exists precisely for this: it installs
  SIGINT/SIGTERM handlers that interrupt the main fiber, then tears down (observed
  exit code 130 in probes regardless of which of the two signals arrived).
- The spawner's scope finalizer is thorough: on scope close with a running child it
  signals the child's process group with `killSignal` (SIGTERM default), waits a
  grace period, escalates to SIGKILL, and awaits exit; group kill falls back to a
  direct child kill (our children are not detached, so a negative-pid group kill
  gets ESRCH). A child that already exited nonzero gets its group killed to clean
  grandchildren.

Empirical results (fake jj sleeping 30 s, signal to the parent PID only):

| Configuration | SIGTERM | SIGINT |
|---|---|---|
| CLI as-is — source, Node 26.6 / 22.20 / launcher | **child orphaned** (parent 143) | **child orphaned** (parent 130) |
| CLI as-is — bundle, Node 26.6 / 20.19 | **child orphaned** | **child orphaned** |
| Control A — `NodeRuntime.runMain` + `Effect.tryPromise` → `jj()` (main-shaped) | **child orphaned** | **child orphaned** |
| Control B — spawn in main fiber's scope + `NodeRuntime.runMain` | **child killed** | **child killed** |

Control A is the finding that matters: signal wiring alone does not fix it.
`runLibrary` lifts library calls with `Effect.tryPromise`, which *abandons* (cannot
cancel) a pending promise on interruption; and each `jj()` call wraps its spawn in
a detached `Effect.runPromise` with its own `Effect.scoped` and self-provided
`NodeServices.layer`. The main fiber's interruption never reaches that inner scope,
so the spawner's excellent finalizer never fires. The child is abandoned exactly as
before — `jj` queries are short, but `refresh` runs `git fetch`, which is the
long-lived case that matters.

## F4 — the committed bundle carries a weaker read-only pin than the source

The bundle was built 2026-09-27 23:54; `archive/src` was modified through 00:14
(custody inventory/stage/vault/retry slices, committed and working-copy). Captured
argv shows a behavioral delta inside that staleness:

- Bundle `jj()`: `readOnly` → `--ignore-working-copy` only; `pinned` → both flags.
- Current source: `readOnly === true || pinned === true` → both
  `--ignore-working-copy --at-op=@` (modes unified).

Consequence: until the final rebuild, bundle-based invocations (health, and any
Node 20 host per F2) run read-only checks **without the `--at-op=@` operation-head
pin** — the exact unpinned shape that the [`jj` adapter's documentation](/archive/src/repository/jj.ts)
records auto-reconciling divergent operation heads (a write) under concurrency.
No fix is applied here by design; the final rebuild will carry the corrected
contract. Flagged so the rebuild is understood as a behavior fix, not just a
freshness refresh.

# Proposal — upstream-only lifecycle wiring (no process framework)

Control B proves the upstream machinery is sufficient when used as intended. The
proposal stays entirely inside `effect/process` + `NodeRuntime` — honoring the
operator's standing correction in [direction0](/design/archive-toolkit/direction0.gpt6astra.md#operator-correction-reuse-process-execution)
against bespoke process runtimes:

1. Run `main` through `NodeRuntime.runMain(program)` instead of
   `Effect.runPromise`, with a teardown that preserves today's contract:
   discard the stdout buffer on any failure/interrupt (the buffer already
   guarantees no partial JSON reaches stdout), report via the existing
   `reportFailure` formatting, exit via the teardown's code.
2. Promote the existing `jjOutcome`/git-outcome shaped Effects to the library seam
   so the CLI composes them directly (borrowing the main fiber's scope) instead of
   calling through `Effect.tryPromise` → async `jj()` → detached
   `Effect.runPromise`. The Promise facade can remain for non-CLI library
   consumers — it just stops being the path the CLI takes. This is a re-scoping of
   the existing boundary, not a new abstraction.

With both pieces, SIGINT/SIGTERM interrupts the fiber, the spawner finalizer
SIGTERM/SIGKILLs the child (group-aware), and the process exits nonzero-by-teardown
with clean stdout. Interruption mid-jj-mutation is no worse than today's orphaning:
jj state is op-log recoverable, custody/health paths are pinned read-only, and a
killed `git fetch` is resumable.

# Verified working (no gaps found)

Against a local colocated fixture, no network — bundle and source agree except
where F4 notes:

- Legacy Ansible contract: flag-only invocation translates to `refresh --json`;
  exactly one stdout JSON line (`{"changed":true,"notices":[]}`, then
  `changed:false` idempotently); legacy `--version BRANCH` spelling accepted under
  refresh without stealing root `--version`.
- stdout purity: parse failures emit 0 bytes on stdout.
- `health` (source) injects both pinned query flags on every jj call (captured
  argv); exits 0 with correct output on a clean fixture.
- `remotes` produces the declared/actual mismatch table and a deliberate
  `--reconcile` hint, exit 1.
- Root help/version/no-args and bash completions behave as documented.

# Reproducing

All probes and fixtures are in `.test-agent/archive-runtime-checks/` (gitignored):
`bin/jj` (fake executable), `signal-probe.sh` (parent-only signal lifecycle),
`runmain-probe.ts` / `scoped-probe.ts` (positive controls A/B), `fixture-repo/`
(local git+jj), captured argv/exit logs. Node versions came from mise
(`mise exec node@<v> -- …`); 20.19.0 was installed ephemerally for the floor cell.

# Cross-references

- [Archive toolkit topic README](/doc/archive-toolkit/README.md): notes the Node
  floor and signal behavior are exercised manually — this document is that
  exercise's evidence and should be linked from its verification section.
- [Compatibility audit](/design/archive-toolkit/compatibility-checks0.glm53.md):
  its acceptance items 3 (shebang needs Node ≥ 20.11) and 19 (Node 20.19 floor,
  exercised manually) are closed out empirically here — item 19 holds for the
  bundle only (F2).
- [Direction](/design/archive-toolkit/direction0.gpt6astra.md): the
  process-execution correction (upstream Effect, no bespoke runtime) that F3's
  proposal follows; its bundle-freshness caveat is quantified by F4.
- [Effect CLI references](/design/archive-toolkit/effect-cli-references0.glm53.md):
  upstream API research this verification confirms against the installed rc118.
- [Custody inventory jj boundary](/archive/src/custody/inventory/jj.ts): consumer
  of the `pinned` mode whose guarantee the stale bundle weakens (F4).
