---
type: Inquiry
title: "Effect CLI references for the archive toolkit — recent local projects, API eras, and precedents"
description: "Read-only survey of ~/src Effect activity (30-day window), the v4 CLI API eras (rc.112 vs rc.117), and concrete command/service/testing/bundling precedents useful for expanding compfuzor's archive toolkit."
status: draft
generated: { by: agent:glm53 (zai glm-5.3-flash#max, opencode harness), at: 2026-09-27 }
verified: { by: agent:glm53, at: 2026-09-27 }
stale_after: 2026-10-27
sources:
  - id: effect-archive
    resource: https://github.com/Effect-TS/effect
    title: "Effect-TS/effect checkout at ~/archive/Effect-TS/effect (4.0.0-rc.117 source, git 64093976, 2026-09-26)"
  - id: local-repos
    resource: ~/src
    title: "jj/git metadata and package.json inventory across ~/src (read-only)"
---

# Effect CLI references — wave 0 (glm53)

## What is up

Compfuzor's archive toolkit ([`/archive/README.md`](/archive/README.md),
`archive/src/repo-jj-archive.ts`) is a **gunshi** CLI today: `cli()`/`define()`
entry, `@gunshi/plugin-completion` for tab completion, per-domain modules
(`refresh.ts`, `harvest.ts`, `health.ts`, `remotes.ts`, `self.ts`), a JSON-only
`refresh --json` mode for Ansible, and a committed vite-plus ESM bundle so
Ansible consumers need no build step.

The question this wave researches (research only, no implementation): **what
would expanding this toolkit with Effect's CLI look like, and what local
precedents exist to mine?** Directions: commands, services, testing, build
bundling — plus which ~/src projects are actively using Effect right now, so
precedents are recent rather than archaeological.

Method: read-only scans. `rg` over `package.json` manifests and imports; `jj
log` / `git log` for activity; no repo was mutated. The Effect source checkout
at `~/archive/Effect-TS/effect` was inspected **first** for the current API, as
directed.

---

## 1. The current Effect CLI API (verify against the archive first)

The checkout at `~/archive/Effect-TS/effect` is **`effect` 4.0.0-rc.117
source**, HEAD `64093976` (2026-09-26, one day old at research time), upstream
`https://github.com/Effect-TS/effect`. README there states v4 is a release
candidate; `main` carries v4 development.

### 1.1 Where CLI lives now

In v4 the CLI is **part of the core `effect` package**, subpath
[`effect/cli`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/) —
there is no separate `@effect/cli` package anymore. Modules at
`packages/effect/src/cli/`:

| Module | Role |
|---|---|
| [`Command.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Command.ts) | Command trees: `Command.make(name, params)`, `withDescription`, `withAlias`, `withSubcommands`, `withSharedFlags`, `withGlobalFlags`, `withHandler`, `run` / `runWith`, `Command.Environment` |
| [`Flag.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Flag.ts) | `Flag.String/Boolean/Literals`, `withAlias/withDefault/withDescription/withHidden/optional/withSchema` |
| [`Argument.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Argument.ts) | Positionals: `Argument.String`, `withSchema`, `optional`, `withDescription` |
| [`Param.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Param.ts) / [`Primitive.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Primitive.ts) | Shared param plumbing |
| [`GlobalFlag.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/GlobalFlag.ts) | `GlobalFlag.setting`, `GlobalFlag.BuiltIns` |
| [`Completions.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Completions.ts) | `Completions.generate` for `bash \| zsh \| fish` from a `CommandDescriptor` — **native replacement for `@gunshi/plugin-completion`** |
| [`Prompt.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/Prompt.ts) | Interactive `Confirm/Select/MultiSelect/AutoComplete/Password/Int/Number/Date/File/Hidden/List`, `Theme` context reference, `Prompt.run` |
| [`CliError.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/CliError.ts) / [`CliConfig.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/CliConfig.ts) / [`CliOutput.ts`](https://github.com/Effect-TS/effect/blob/main/packages/effect/src/cli/CliOutput.ts) | Error taxonomy, config, rendering |

Everything in `effect/cli` is marked `@stability unstable`, `@since 4.0.0` —
expect continued movement between RCs.

### 1.2 The canonical example (upstream, current)

[`ai-docs/src/70_cli/10_basics.ts`](https://github.com/Effect-TS/effect/blob/main/ai-docs/src/70_cli/10_basics.ts)
is the up-to-date "getting started" — the single best first read:

- Reusable flags defined outside commands (`Flag.String("workspace").pipe(Flag.withAlias("w"), Flag.withDefault(...))`).
- Parent/root command with `Command.withSharedFlags`, subcommands read parent input by **yielding the parent command** inside the handler.
- Schema validation at parse time (`Argument.withSchema(Schema.NonEmptyString)`) so handlers only see valid input.
- Compose + run: `tasks.pipe(Command.withSubcommands([create, list]), Command.run({ version: "1.0.0" }), Effect.provide(NodeServices.layer), NodeRuntime.runMain)`.
- `Command.withExamples([...])` for help docs.

### 1.3 Running and testing entry points

From `Command.ts` source:

- `Command.run({ version, renderErrors? })` — dual; reads argv from
  `Stdio.Stdio.use(({ args }) => ...)`. Returns
  `Effect<void, E | CliError, R | Command.Environment>`.
- `Command.runWith(command, config)(args)` — explicit argv; the docstring says
  verbatim: *"Use when you need to test CLI applications or programmatically
  execute commands with specific arguments."* Help always renders; parse errors
  and `CliError.UserError` render via the installed `CliOutput.Formatter`
  unless `renderErrors: false`.
- Testing services fixture (in `Command.ts` jsdoc, `import.meta.vitest`
  example): `FileSystem.layerNoop({})`, `Path.layer`, **`Stdio.layerTest({})`**,
  a hand-built `Terminal.make({...})` with fixed 80×24 and dead input, and a
  stubbed `ChildProcessSpawner` — merged as `CliTestLayer`. This is the
  upstream-endorsed shape for in-process CLI tests.

### 1.4 Version distinctions that matter locally

There is a hard fault line inside v4 itself:

- **Pre-2026-09-22 RCs (≤ rc.116)**: CLI subpath is `effect/unstable/cli`,
  lowercase constructors (`Flag.boolean`, `Argument.string`).
  `Command.run(command, config)` / `Command.runWith` exist.
- **Commit
  [`1b4461ec`](https://github.com/Effect-TS/effect/commit/1b4461ec3a17e527dd39576f1783f73354187f1f)
  "Move unstable Effect modules to top-level paths (#8354)", 2026-09-22**: all
  unstable modules (`ai`, `cli`, `cluster`, `observability`, `sql`, …) moved to
  top-level subpaths (`effect/cli`, `effect/sql`, …) — see
  [`MIGRATION.md`](https://github.com/Effect-TS/effect/blob/main/MIGRATION.md)
  ("no compatibility exports for the old paths"; moving does not stabilize the
  APIs). Constructors are now capitalized (`Flag.String`, `Argument.String`).
- **Published rc.117 tarballs still carry `dist/unstable/cli/` barrel
  re-exports on disk**, but the package `exports` map no longer exposes
  `./unstable/*`. Bundler-style resolvers can still find them; strict Node ESM
  cannot. Concretely observed: `effect-sql-turso` (pinned rc.117, active 6 days
  ago) still imports `effect/unstable/sql/*` and only resolves because of
  bundler-style resolution — a live cautionary example that **rc bumps inside
  v4 are import-path-breaking** and pin discipline matters.
- **v3 era (for contrast)**: `@effect/cli` was a separate package (e.g.
  `0.73.2`) with a different param API (`Args.text`, `Options.*`) and
  `Command.make(...).pipe(Command.withHandler(...))`. Nothing in the recent
  local window uses it except the stale `ep-cli` (§3, precedent D).

Implication for any toolkit work: pin to the archive's rc.117 shape
(`effect/cli`, capitalized constructors), but expect to translate when reading
local rc.112-era code (`effect/unstable/cli`, lowercase constructors).

---

## 2. ~/src Effect activity, last 30 days (evidence)

Window: 2026-08-28 → 2026-09-27. Evidence: `git log -1 --format=%cs` where a
Git repo exists; `jj log` authored timestamps (excluding today's
"workspace resync 2026-09-27" working-copy markers) for jj workspaces;
`fd --changed-within 30d` file mtimes as corroboration. ~76 local projects
declare an `effect` dependency; the table lists those with activity evidence in
the window plus the most relevant slightly-older ones.

### 2.1 Standalone projects (git-dated)

| Project | Last commit | Effect version | Notes |
|---|---|---|---|
| `opencode-session-move` | 2026-09-27 | rc.112 (opencode family) | session-move opencode plugin |
| `opencode-provider-metrics` | 2026-09-27 | **4.0.0-beta.65** | monorepo; carries the `effectCmd` yargs↔Effect bridge (§4-B) |
| `vosse` | 2026-09-24 | (no effect dep) **gunshi ^0.37.1** | ATProto-adjacent app; gunshi-family precedent |
| `openquarter` | 2026-09-24 | rc.112 | |
| `opencodance` | 2026-09-24 | 4.0.0-beta.101 | |
| `opencoattails` | 2026-09-24 | **rc.115** | has `packages/cli` on `effect/unstable/cli` (§4-A sibling) |
| `opencontinuer` | 2026-09-23 | rc.112 | |
| `persist-log` | 2026-09-22 | **rc.117** | current-version services/eventlog library |
| `opencode-sub-interactive` | 2026-09-22 | rc.112 | |
| `opencode-plugact` | 2026-09-22 | rc.112 | |
| `ocyc` | 2026-09-21 | rc.115 + **gunshi ^0.36** | credential-rotation CLI; closest structural sibling to repo-jj-archive (§4-C) |
| `effect-sql-turso` | 2026-09-21 | **rc.117** | current-API SQL adapter; subpath-migration cautionary tale (§1.4) |
| `dl` | 2026-09-21 | **rc.116 + gunshi ^0.28** | **the archive fetcher itself**; gunshi+Effect hybrid, CLI tests, recent rc.116 research (§4-C) |
| `opencoattails-fxcut` | 2026-09-20 | rc.115 | |
| `openpetname` | 2026-09-19 | rc.112 | |
| `opencode-shell-sessionids` | 2026-09-19 | rc.112 | |
| `openatomic` | 2026-09-13 | 4.0.0-beta.101 | |
| `openvariant` | 2026-09-11 | rc.112 | |
| `open2all` | 2026-09-11 | rc.115 | `effect/unstable/cli` `Command.make`/`Command.run` app CLI |
| `lore-code` | 2026-09-08 | rc.112 | |
| `opencode-subagent-control` | 2026-09-07 | rc.112 | |
| `opencode-agent-complete` | 2026-09-07 | rc.112 | |
| `opencode-term-v2` | 2026-09-06 | rc.112 | |
| `opencode-lastact` | 2026-09-04 | rc.112 | |
| `opencode-watchman` | 2026-09-01 | rc.112 | |
| `first-compute` | 2026-09-01 | 4.0.0-beta.83 | |

### 2.2 jj-workspace family (authored timestamps from `jj log`)

These are opencode-plugin forks sharing one shape (`packages/cli` +
`effect/unstable/cli` framework, §4-A). "Last real commit" excludes the
2026-09-27 workspace-resync markers:

| Project | Last real commit | Notes |
|---|---|---|
| `opencode-args` | ~4 days (2026-09-23) | "docs(cli): explain scoped TUI argument route", "fix(cli): keep scoped TUI args quiet outside TUI" — active **CLI** work |
| `opencode-working` | ~3 days | docs(compose) work |
| `opencode-bus-smart` | ~4 days | "research observability wiring and Effect v4 metric plan" — verified-against-source v4 notes (§5) |
| `opencode-watchman-vcs-core` | ~3 weeks | "docs(watchman): record Core VCS implementation boundary" |
| `opencode-systemd` | ~4 weeks | prompt-api service design drafts |
| `opencode-acp` | ~4–5 weeks | carries `@effect/vitest` drive tests; `packages/cli/test/commands.test.ts` parse tests (§4-A) |
| also in window (mtime evidence, AGENTS.md/CONTRIBUTING touched ≤30d) | — | `opencode-watchman-{again,old,v2-readd,owned-observation,observation-synthesis,vcs-observation}`, `opencode-{terminate,rerun,model-ident,subagent-recovery,pulse-3fps,cache-time,bus-smart-old,bus-smart-astr-what,export-qa,explicit-port,jj-vcs}` |

Outside the window but relevant: `effect-patterns-opencode` (7 months stale)
and `opencode-plugin-title` / `opencoattails-opencode` (beta.98-era, house the
`effect-cmd.ts` bridge, §4-B).

---

## 3. Version map (single view)

| Era | Subpath | Constructors | Local users (activity) |
|---|---|---|---|
| v3 (`effect` 3.x) | `@effect/cli` package | `Args.*`, `Options.*` | `effect-patterns-opencode` (stale 7mo) |
| v4 beta.65–rc.116 (≤2026-09-22) | `effect/unstable/cli` | lowercase: `Flag.boolean`, `Argument.string` | opencode-* family (rc.112), opencoattails/open2all/ocyc (rc.115), dl (rc.116), betas elsewhere |
| v4 rc.117 / main (≥2026-09-22) | **`effect/cli`** | capitalized: `Flag.String`, `Argument.String` | archive checkout; `persist-log` pinned (but see its sibling effect-sql-turso's stale imports) |

---

## 4. Pattern precedents (file-level)

### A. v4 native CLI framework — the opencode-* family (rc.112, most active)

`packages/cli/src/` in `opencode-working` (3 days), `opencode-args` (4 days),
`opencode-bus-smart`, `opencode-watchman-vcs-core`, `opencode-systemd`,
`opencode-acp`, `opencode-otel`, … all share:

- **Spec tree** (`framework/spec.ts`): a tiny typed wrapper over
  `Command.make(name, params)` + `withDescription`/`withAlias`/`withSubcommands`
  that keeps a plain-object tree of `{name, spec, params, commands, aliases}`.
  Notable detail: Effect supports one native alias; extra aliases become sibling
  commands sharing params — a documented workaround with explanatory comment.
- **Lazy handlers** (`framework/runtime.ts`): the command tree is built
  immediately, but each `Command.withHandler` does
  `Effect.promise(handler.load)` → dynamic `import()` of the handler module.
  Startup stays fast; handler code loads on dispatch. Handler requirement types
  are declared up front
  (`FileSystem | Global.Service | Npm.Service | Updater.Service | Config.Service | Scope.Scope`).
- **Global flags**: `GlobalFlag.setting("print-logs")({flag: Flag.boolean(...).pipe(...)})`
  then `command.pipe(Command.withGlobalFlags([PrintLogs]))`;
  `GlobalFlag.BuiltIns` spread alongside.
- **Run**: inside `Stdio.Stdio.use(({ args }) => ...)`, prepare argv (below),
  then `Command.runWith(command, { version })(prepared.args)` typed as
  `Effect<void, unknown, Command.Environment>`.
- **Env-var argument defaults** (`packages/cli/src/args/environment.ts`):
  `prepareArguments(commands, args, process.env, globals)` splices
  `OPENCODE_ARGS`/`OPENCODE_TUI_ARGS` values after real argv (before `--`),
  validates against the flags actually supported by the resolved command route,
  and emits warnings. Directly analogous to compfuzor's env-var conventions
  (`GIT_REMOTE`, `GIT_UPDATE`, …) in
  [`/tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks).
- **Parse-level tests without spawning**
  (`opencode-acp/packages/cli/test/commands.test.ts`): swap in a capture
  handler and run real argv through the real parser:

  ```ts
  const command = Commands.spec.pipe(
    Command.withHandler((input) => Effect.sync(() => (sessions = input.session)))
  )
  await Effect.runPromise(
    Command.runWith(command, { version: "test" })(["-s", "first", "--session", "second"])
      .pipe(Effect.provide(NodeServices.layer))
  )
  ```

  Repeated-flag ordering and zero/one-value semantics asserted this way. Also
  `packages/cli/test/cors.test.ts`, `test/fixture/upgrade.ts` in the same
  family. *Translate `effect/unstable/cli` → `effect/cli` when reusing.*

### B. Bridge adapter — yargs shell, Effect handlers (incremental adoption)

`opencode-provider-metrics` (active today), `opencode-plugin-title`,
`opencoattails-opencode`:
`packages/opencode/src/cli/effect-cmd.ts` (~94 lines, identical across forks):

- `CliError extends Schema.TaggedErrorClass<CliError>()("CliError", {message, exitCode?})`
  + `fail(message, exitCode)` — typed user-visible failure.
- `effectCmd({command, describe, builder, instance?, handler})` wraps the
  existing yargs `cmd()` factory; the Effect handler runs via
  `AppRuntime.runPromise(...)`; instance services provided per-invocation and
  disposed with `Effect.ensuring(store.dispose(ctx))` on every Exit.
- Handlers are `Effect.fn("Cli.<name>")(function*(args){...})` — a named
  tracing span per CLI invocation for free.
- The docstring states the migration strategy outright: keep yargs as the
  shell until all commands are `effectCmd`, then swap the factory for
  `effect/cli`'s `Command.make` **without touching handler bodies**. That is
  exactly the posture the archive toolkit would take if it grew Effect services
  under the existing gunshi shell.

### C. gunshi + Effect hybrid — the toolkit's current family

- **`dl`** (`~/src/dl`, rc.116 + gunshi ^0.28, active 2026-09-21) — and it is
  *the canonical `~/archive` fetcher*, i.e. the toolkit's closest sibling in
  purpose as well as stack:
  - per-command modules `src/command/*.ts` with colocated `*.test.ts`;
  - gunshi `defineWithTypes<CommandParams>()`, plugin extensions
    (`POSITIONAL_INPUT_PLUGIN_ID`) fetched from `ctx.extensions`;
    `requireExtensions` guard;
  - planner/service layer (`planner.run({inputs, subcommand})`) — commands are
    thin, logic lives in testable services;
  - CLI-level tests spawn the real entry with `execFile(process.execPath,
    ["dl.ts", ...args])` — node type-stripping, no build — asserting exit
    codes and stderr text for `--dry-run`/`--noop` gating
    (`src/cli.dry-run.test.ts`, `cli.page.test.ts`, `cli.tangle.test.ts`);
  - recent design commits: "Model B research: rc.116 capability inventory",
    "design: put Effect in charge of campaigns and typed durable work"
    (`design/` in that repo).
- **`ocyc`** (`~/src/ocyc`, rc.115 + gunshi ^0.36, active 2026-09-21):
  `src/cli/<command>.ts` + colocated tests (`ls.test.ts`, `parse.test.ts`,
  `fleet-*.test.ts`), gunshi plugins for store/auth/config/quota, env-fallback
  module (`env.ts`, `env-fallback.test.ts`) — env-defaults precedent.
- **`vosse`** (`~/src/vosse`, gunshi ^0.37, 2026-09-24): gunshi-only, no
  effect — shows the plain-gunshi end of the same family.
- **compfuzor today**: `/archive/src/repo-jj-archive.ts` — `cli()`/`define()`,
  completion plugin, JSON-line contract for Ansible
  ([`/archive/README.md`](/archive/README.md)).

### D. v3 `@effect/cli` — contrast only (stale)

`effect-patterns-opencode/packages/ep-cli` (effect 3.19, `@effect/cli`
0.73.2, stale ~7 months): `Command.make("list").pipe(Command.withDescription(...),
Command.withHandler(() => Effect.gen(...)))`, services via yield
(`Display`, `Logger`, `SkillsAPI`), `src/runtime/test.ts` env-layer overrides,
`src/__tests__/cli-surface.test.ts` running `runCli(argv)` through
`Effect.runPromiseExit` with mocked console. Useful as the "old API" reference
so v4 translations are conscious; not a target shape.

### E. Upstream in-repo examples (rc.117, current API)

- [`ai-docs/src/70_cli/10_basics.ts`](https://github.com/Effect-TS/effect/blob/main/ai-docs/src/70_cli/10_basics.ts) — full subcommand app (§1.2).
- `packages/effect/typetest/cli/Command.tst.ts`, `Param.tst.ts`, `Prompt.tst.ts` — type-level usage contracts.
- `packages/effect/src/cli/Command.ts` jsdoc `CliTestLayer` — in-process test services (§1.3).
- `packages/tools/openapi-generator/test/OpenApiGeneratorCli.test.ts` — uses `effect/cli`'s `CliOutput` in tests (current-era CLI testing in the wild, upstream).
- `packages/platform/node-shared/test/fixtures/node-terminal.ts` — `Prompt` terminal fixture.
- Root [`LLMS.md`](https://github.com/Effect-TS/effect/blob/main/LLMS.md) and `ai-docs/src/` — source-first LLM docs the repo generates for itself.

---

## 5. Services, observability, build/bundling pointers

- **Runtime**: v4 idiom is `Effect.provide(NodeServices.layer)` +
  `NodeRuntime.runMain` (from `@effect/platform-node`) — see §1.2. The
  opencode-* entrypoints additionally use lazy per-command handler imports so
  cold start stays lean (§4-A).
- **Observability**: `opencode-bus-smart` `design/bus-smart/observability0.glm53.md`
  (4 days old) is a **verified-against-source** account of Effect v4 at
  rc.112→rc.115: `effect/unstable/observability` `OtlpTracer`/`OtlpLogger`,
  `Metric.*` registry internals, and an explicit compatibility-gap check
  rc.112→rc.115 ("none for this scope"). Its companion
  `observability-implementation0.glm53.md` shows the wiring. Cite these rather
  than re-verifying Metric/OTLP APIs.
- **`Effect.fn("Cli.<name>")` spans** (§4-B) — per-invocation tracing with no
  extra wiring; pairs with the bus-smart OTLP story.
- **Testing**:
  - parse-level: `Command.runWith` + `NodeServices.layer` (§4-A) — no process spawn;
  - whole-CLI: spawn `node <entry>.ts` and assert exit/stderr (`dl`, §4-C) —
    matches compfuzor's run-`.ts`-directly convention and its pytest Ansible
    integration tests ([`/archive/README.md`](/archive/README.md) "Build, checks, tests");
  - in-process with test services: upstream `CliTestLayer` (`Stdio.layerTest`, fixed `Terminal`) (§1.3);
  - `@effect/vitest` exists locally in `opencode-acp/packages/drive` tests — heavier simulation-style testing, probably overkill for the toolkit.
- **Bundling**: compfuzor already packs the toolkit as a single committed ESM
  bundle (`vite-plus` `pack`, node20.19, `clean:false`, no code splitting) —
  [`/vite.config.ts`](/vite.config.ts). Adding `effect/cli` would grow that
  bundle (effect core is substantial; `dl` ships unbuilt via node type
  stripping instead, `ocyc` uses a `#!/usr/bin/env node` `.ts` entry). The
  committed-bundle-vs-run-from-source tradeoff is already documented in
  [`/archive/README.md`](/archive/README.md); an Effect dependency makes the
  bundle heavier but does not change the mechanism. Note `codeSplitting: false`
  is load-bearing for the ansible transport — lazy dynamic imports (§4-A)
  would defeat single-file packing, so the lazy-handler pattern conflicts with
  the committed-bundle lane unless code splitting stays off.

---

## 6. Recommended precedents (ranked for the archive toolkit)

1. **§4-A (opencode-* `packages/cli` framework)** — the only substantial,
   current, locally-proven v4 CLI body of code: spec tree, lazy handlers,
   global flags, env-arg defaults, parse tests. Mine it for structure; import
   paths and constructor case need rc.117 translation.
2. **§4-C `dl`** — same job (archive management), same shell (gunshi), Effect
   underneath, thin commands over a planner service, excellent CLI test
   hygiene, and current rc.116 research docs. Best model for *how much* Effect
   to adopt without moving off gunshi.
3. **§4-B `effectCmd` bridge** — the lowest-risk incremental path: keep the
   gunshi surface, make handlers Effects, swap the factory later. The
   typed-`CliError` + `Effect.ensuring` disposal + `Effect.fn` span details are
   directly liftable.
4. **§1.2/§1.3 upstream basics + test fixture** — authoritative rc.117 API and
   the in-process testing shape; the `Completions.generate` module is the
   in-Effect answer to the toolkit's current `@gunshi/plugin-completion`.
5. **§5 bus-smart observability docs** — verified v4 Metric/OTLP guidance if
   the toolkit ever needs instrumentation.

Caveats to carry into any design: everything `effect/cli` is `@stability
unstable`; rc bumps break import paths (§1.4, effect-sql-turso evidence); the
opencode-* precedents are on rc.112 and pre-migration; and the single-bundle
ansible transport constrains laziness.

---

## Cross-references

- [`/archive/README.md`](/archive/README.md) — the toolkit this wave aims to inform: gunshi commands, Ansible JSON contract, bundle transport, safety ordering.
- [`/design/repo-jj-archive/draft0.gpt6sol.md`](/design/repo-jj-archive/draft0.gpt6sol.md) and [`draft1.gpt6sol.md`](/design/repo-jj-archive/draft1.gpt6sol.md) — original design lineage of the toolkit the README links.
- [`/design/repo-jj-archive/incident-ghost-heads.glm53.md`](/design/repo-jj-archive/incident-ghost-heads.glm53.md) — the `health`/ghost-heads safety work any new CLI surface must preserve.
- `~/src/dl/design/` (Model B / rc.116 capability inventory) — sibling repo's current Effect adoption research.
- `~/src/opencode-bus-smart/design/bus-smart/observability0.glm53.md` — verified Effect v4 observability notes (rc.112→rc.115).
- Sibling waves in this directory (`direction0.gpt6astra.md`, `custody-contracts0.gpt6sol.md`) were deliberately **not** read, per wave-independence rules.
