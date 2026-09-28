---
type: VerificationPlan
title: Archive toolkit CLI migration — regression acceptance matrix and test gaps
description: Read-only verification plan for migrating repo-jj-archive from Gunshi to Effect CLI plus a self-contained single-file bundle; every behavior the current 14-test suite and hand probes pin down, and the exact tests still missing.
resource: /design/archive-toolkit/compatibility-checks0.glm53.md
tags: [compfuzor, archive, cli, gunshi, effect, regression, testing]
status: draft
generated: { by: model:glm53, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: cli-contract
    resource: /archive/README.md
    title: Archive toolkit user contract
  - id: cli-entry
    resource: /archive/src/repo-jj-archive.ts
    title: Gunshi CLI composition under migration
  - id: launcher
    resource: /script/repo-jj-archive.ts
    title: Source-first launcher with bundle fallback
  - id: existing-suite
    resource: /tests/integration/repo_jj_archive.test.py
    title: Integration suite used as the regression baseline
  - id: ansible-consumer
    resource: /tasks/compfuzor/repo_jj_archive.tasks
    title: Ansible argv and stdout parsing contract
---

# Compatibility checks for the Effect CLI / single-file bundle migration

## Situation

The archive toolkit's CLI surface ([`archive/src/repo-jj-archive.ts`](/archive/src/repo-jj-archive.ts),
Gunshi 0.37 + `@gunshi/plugin-completion`) is being migrated to Effect CLI, and
the committed [`archive/repo-jj-archive.mjs`](/archive/repo-jj-archive.mjs)
bundle must stay a self-contained single file. Two consumers depend on the
surface without knowing the framework behind it: the Ansible tasks
([`repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)) that parse
exactly one JSON line, and the launcher
([`script/repo-jj-archive.ts`](/script/repo-jj-archive.ts)) that picks source
vs. bundle. A sibling wave is researching Effect CLI upstream capabilities;
this document stays on compfuzor ground: **what is verifiably true today, and
which tests would catch a regression during the rewrite.**

Method: read the four production files plus the suite, then hand-probed the
current CLI's parsing and failure behavior in
`.test-agent/compat-probe/` (scratch, since removed; every probe is
reproducible from the tables below). Baseline: the full suite ran
**14 passed in ~34s** twice — before and after the in-flight
`repository/`/`recovery/` module split landed, confirming the CLI entry is
unaffected by the library reorganization. Environment: Node v26.6.0, jj
0.45.1, git 2.55.0, Python 3.14.6. No production archive was touched; no
code/test/package file modified.

## Verified current CLI behavior (probe evidence)

All probes ran the source entry via `node` and the launcher via its shebang;
behavior was identical unless noted.

### Stream purity and exit codes

| Invocation | rc | stdout | stderr |
|---|---|---|---|
| `refresh --json --dest X --repo Y --label l --update maybe` | 1 | empty | `repo-jj-archive: argument --update: invalid choice: 'maybe' (choose from 'true', 'false')` |
| `remotes --dest … --repo … --remotes 'not-json'` | 1 | empty | `repo-jj-archive: Unexpected token 'o', "not-json" is not valid JSON` |
| `remotes … --remotes '[]'` | 1 | empty | `repo-jj-archive: --remotes must be a JSON object mapping remote names to URLs` |
| `refresh … --submodules` (existing archive) | 1 | empty | `repo-jj-archive: GIT_SUBMODULES requires explicit submodule safety handling; disable it for this archive render` |
| `refresh … --depth 0` | 1 | empty | `repo-jj-archive: GIT_DEPTH must be positive` |
| unknown command `bogus` | 1 | empty | `repo-jj-archive: Command not found: bogus` |
| unknown flag `refresh --bogus` | 1 | empty | aggregated: required-arg messages **plus** `Unknown option: --bogus` |
| missing required `refresh --json` | 1 | empty | `Optional argument '--dest' is required; Optional argument '--repo' is required; Optional argument '--label' is required` |
| runner present but runner file missing (launcher) | 1 | 0 bytes | `repo-jj-archive: Cannot find module '…/archive/repo-jj-archive.mjs' imported from …/script/repo-jj-archive.ts` |
| success `refresh --json` | 0 | exactly one JSON line | empty |

Error formatting is `repo-jj-archive: ` + `error.message`, with
`AggregateError` members joined by `"; "` — the launcher and the entry
duplicate this catch. Effect's error rendering (pretty cause trees, multi-line
reports) is a direct threat to the `"--dest" in stderr`-style assertions; see
matrix below.

### argv parsing quirks (each is a pinned compatibility surface)

| Probe | Result | Risk if Effect differs |
|---|---|---|
| root `--help` | rc0, usage listing all commands incl. `complete` | low |
| root (no args) | rc0, `Run repo-jj-archive --help for commands.` | low |
| root `-v` | rc0, `0.1.0` on stdout | **single-dash skips the legacy translation** — asymmetric with `--version` |
| root `--version` | rc1, empty stdout, stderr = required-arg validation | **hijacked**: legacy translation turns it into `refresh --branch <no value>`; root version is unreachable. Pin or fix deliberately |
| `--help --version` | rc0, `0.1.0` wins over help | parser precedence quirk |
| `-V` | rc1, `Unknown option: -V`, stdout empty | short-flag set is exactly `-h`, `-v` |
| `refresh -v` | rc0, `0.1.0` | per-command `-v/--version` is Gunshi-reserved |
| `refresh --help` | rc0, **exactly one** `--json` mention (suite asserts `.count("--json") == 1`) | Effect help renderers often repeat global flags or add sections |
| `--dest=X` equals form | accepted | Effect named-option syntax must keep it (Ansible argv uses space form, humans use `=`) |
| `--dest --label` (value looks like flag) | `--label` becomes *unknown option*; `--dest` not consumed | **dangerous inversion**: if Effect consumes the next token as the value, `--dest` becomes `--label` and could `mkdir` a bogus path |
| `--freshen true` (boolean with trailing token) | rc0, `true` silently ignored | Effect may error on stray positional or treat it as one; pin either way |
| duplicate flag `--archive-dir a --archive-dir <real>` | last wins, rc0 | Effect may error or first-wins |
| `self -- --archive-dir=<real>` (real fixture dir) | `--` honored: override NOT applied, output identical to no-override run | stop-flag parsing must survive |
| `self extra` (unknown positional) | rc0, silently ignored | strict positional rejection would be a behavior change |
| `complete bash\|zsh\|fish\|powershell` | rc0, 102/219/233/251-line scripts referencing `repo_jj_archive` | completion must keep the binary name and per-command flags |
| `complete bogus` | **rc0, both stdout and stderr empty** — silent no-op | pin (or decide to error) |
| `complete` (no arg) | rc0, stdout `":4\n"`, stderr `":4\n"` (completion directive `:4` = NoFileComp) | pin or clean up |
| legacy flag-only `--dest … --repo …` (no subcommand) | == `refresh … --json`; suite asserts JSON equality with explicit form | the translation `args[0]?.startsWith("--") && args[0] !== "--help"` → prepend `refresh`, append `--json` **last** must be replicated exactly |
| `--version BRANCH` (legacy spelling) | translated to `--branch` **only when `argv[0] == "refresh"`**; exercised by every suite `render()` call | the conditional scope of the translation is easy to lose |

### Launcher resolution (verified)

| Tree shape | Behavior |
|---|---|
| source + `node_modules/gunshi` + `node_modules/@gunshi/plugin-completion` all present | imports `archive/src/repo-jj-archive.ts` (type-stripped, no bundler) |
| any of the three missing | falls back to `archive/repo-jj-archive.mjs` — **including** "source present, only gunshi dep" (partial deps → bundle) |
| source present + deps present, but source broken (`throw` at import) | **no fallback**: rc1, stderr `repo-jj-archive: broken source`, stdout empty |
| neither source nor bundle | rc1, stderr `Cannot find module …`, stdout 0 bytes |
| launcher + bundle copied standalone, source replaced with poisoned `throw` file | rc0, bundle serves the request (suite `test_launcher_uses_standalone_bundle_without_source_or_node_modules`) |

The dependency check is a bare `stat()` on three paths in `sourceFiles`
([`script/repo-jj-archive.ts`](/script/repo-jj-archive.ts) lines 25–29). After
migrating to Effect, **gunshi will not be imported anymore** — if the list is
not rewritten to the Effect package set in lockstep, the launcher silently
degrades to bundle-always in dev checkouts and the source path becomes dead
code that no test fails on (the existing suite only exercises the
bundle-fallback direction).

### Bundle facts (verified)

- `archive/repo-jj-archive.mjs` is committed, mode `100755`, 5144 lines /
  ~174 KB, shebang identical to the source entry, ends `export { main }`,
  embeds `version: "0.1.0"`.
- Every static import is `node:*`; **zero** bare-specifier imports and zero
  dynamic `import(` in the bundle today (rg over the file).
- Direct execution works both ways: `node archive/repo-jj-archive.mjs refresh
  --json …` and `./archive/repo-jj-archive.mjs refresh --json …` on a fixture.
- The bundle carries the same `process.argv[1]` realpath main-guard, so
  importing it (as the launcher does) never double-runs.
- **No test asserts bundle freshness** (that a rebuild is a no-op) or
  self-containment; both are currently maintained by hand ("Rebuild and
  commit the bundle with source changes" in the README).

## Regression acceptance matrix

Legend: **P** = preserve byte-for-byte or test-equivalent; **D** = deliberate
decision required before/with the migration (either choice is fine, but a test
must encode the chosen behavior); **M** = migration-only invariant, new test.

| # | Surface | Class | Contract to hold | Why it can break |
|---|---|---|---|---|
| 1 | `main()` export + argv[1] realpath guard in both entries | P | Launcher imports `{ main }` from source *and* bundle; guard no-ops when imported | Effect CLIs usually own process startup (`Effect.runPromise`); the exported-`main` shape must be kept |
| 2 | Launcher `sourceFiles` dep list | M | Must name exactly the runtime deps of the new source entry (every bare import in `archive/src/repo-jj-archive.ts` has a `node_modules/<pkg>` stat entry) | Stale gunshi/plugin entries → source path permanently dead, silently |
| 3 | Shebang `#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON` | P | On `script/repo-jj-archive.ts`, `archive/src/repo-jj-archive.ts`, and `archive/repo-jj-archive.mjs`, mode 0755; suite executes the runner **directly** (no `node` prefix) | Effect docs sometimes suggest different flags; `env -S` and the warning flag need Node ≥ 20.11 (engines floor 20.19, satisfied) |
| 4 | stdout failure purity | P | Any failure: rc ≠ 0, stdout **empty**, single-line `repo-jj-archive: <detail>` on stderr; `AggregateError` join stays or tests updated | Effect's default error rendering / logger is multi-line and may interleave; `renderValidationErrors: null` and `renderHeader: null` equivalents must exist |
| 5 | `--json` single-line success | P | Exactly one JSON line, no header, no progress chatter; suite's `json.loads` of full stdout would catch violations | Effect logger/console layering; `Console` service default may add formatting |
| 6 | Diagnostics substrings asserted by the suite | P | `not a colocated Git checkout`; declared+actual URLs; `remotes --dest`/`--reconcile` hints; `name\t"declared"\t"actual"` table with `(missing)`; `ghost commit`; `heal --dest`; `"Object "` absence; `--yes`; `--dest` on missing-required; `BOOKMARK CREATED  main ->` (two spaces); `REPO NOTICE` | These are thrown `Error.message`s, framework-independent — safe **only if** the error propagation path stays single-message. Effect tagged errors with pretty printers would wrap them |
| 7 | Validation-error aggregation shape | D | Today: all problems joined in one stderr line (`Optional argument '--dest' is required; …; Unknown option: --bogus`). Keep aggregate, or switch to Effect's per-error style — but rc1 + empty stdout is non-negotiable | Effect validation collects differently |
| 8 | Legacy argv translation | P | First-arg `--x` (≠`--help`) → `refresh` + trailing `--json`; `--version`→`--branch` only under `refresh`; translation runs **before** parsing | Must be re-expressed on top of Effect's parser as a pre-pass, or Effect's strict parser will reject the raw legacy argv |
| 9 | Parsing quirks table above | D each | equals-form, `--` stop-flag, last-wins duplicates, boolean+stray-token, dash-leading values, unknown positionals ignored, `-V` unknown | Effect's parser (getOption/args) has its own semantics for nearly every row |
| 10 | Help surface | D | `--help` rc0 with usage; `refresh --help` mentions `--json` exactly once; no-args hint line; help text name `repo-jj-archive` | Effect help renderers have richer layouts; the `.count("--json") == 1` assertion is the sharp edge |
| 11 | Version surface | D | Today: `-v`/`refresh -v` → `0.1.0` (rc0, stdout); root `--version` hijacked → validation error; `--help --version` → version wins. Pick: reproduce quirks, or make root `--version` real (then update matrix row + tests) | Gunshi-reserved `--version` vs Effect built-ins |
| 12 | Completion | M+D | `complete <shell>` for bash/zsh/fish/powershell: rc0, non-empty, references `repo_jj_archive`/`repo-jj-archive`. Current plugin is `@gunshi/plugin-completion`; Effect has no equivalent bundled generator — the migration must source one (or shell out) **or** keep a Gunshi-free hand-rolled generator. `complete bogus` silent-rc0 and no-arg `:4`-on-both-streams: pin or clean up | Highest-effort row: the feature has **zero tests today** and no obvious Effect-native replacement |
| 13 | Bundle self-containment | M | Committed single `.mjs`: only `node:` static imports, no dynamic `import(`, shebang + mode 0755 + `export { main }` | Effect + platform packages inflate the bundle (fine) but may pull conditional exports/worker files; verify rolldown/vite inlines all |
| 14 | Bundle freshness | M | Rebuild (`vp pack`) must be a no-op against the committed file | No test today; hand discipline so far |
| 15 | Direct bundle execution | M | `archive/repo-jj-archive.mjs` runs via shebang **without** launcher and outside the project tree | Only launcher-mediated execution is tested today |
| 16 | Ansible layer untouched | P | `repo_jj_archive.tasks` argv form (incl. bare `--submodules`, `to_json` remotes, string `--update`), `changed_when` `from_json` gated on `rc == 0`; failure surfaces runner message, not `from_json` parse error | Tasks file is framework-blind — hold the line that it does **not** change |
| 17 | cwd independence | P | Behavior identical from any cwd (suite already mixes `archive.parent`, `tmp`, `ROOT`) | Effect `FileSystem`/cwd services could introduce implicit cwd resolution |
| 18 | Subprocess boundary | P | `jj`/`git` via `execFile` argv arrays, `--no-pager --color=never`, no shell interpolation; 64 MB maxBuffer | Effect `Command` module equivalent must keep array-exec and capture semantics |
| 19 | Node engines floor | M | Runs under Node 20.19 (shebang `--disable-warning`, Effect runtime support matrix) | Dev runs on 26; floor only exercised manually today |
| 20 | Signals / interrupts | M | SIGINT/SIGTERM: no stdout pollution, exit nonzero (Ansible may kill renders) | Effect runtimes can install interrupt handlers that print |

## Test gaps → proposed exact tests

Gaps ordered by migration risk. All are additions to
[`tests/integration/repo_jj_archive.test.py`](/tests/integration/repo_jj_archive.test.py)
(same fixture helpers, `.test-agent` scratch) unless noted. Nothing existing
needs to change for rows 1–7; rows 8–12 close outright holes that exist
**already today**, independent of the migration.

**G1 — root help/version/no-args contract (D-decision encoded).**
`test_root_help_version_and_noargs_contract`: assert
`--help` rc0 + stdout contains `USAGE:`/`refresh`/`repo-jj-archive`;
no-args rc0 + exact hint line; `-v` rc0 stdout `0.1.0`; `--version` rc1 + empty
stdout + stderr matches the required-arg validation (documents the hijack);
`-V` rc1 + `Unknown option: -V`. If the migration decides to make root
`--version` real, this test flips with the decision — that is its job.

**G2 — strict validation goes to stderr, never stdout.**
`test_validation_errors_never_touch_stdout`: for unknown command (`bogus`),
unknown flag (`refresh --bogus`), missing required (`refresh --json`): rc1,
`stdout == ""`, and the specific substrings from matrix row 6/7. (Partially
covered today only for the missing-`--dest` legacy path.)

**G3 — argv parsing quirks.**
`test_option_parsing_quirks_are_stable`: equals-form detection works;
`--`-separator ignores a following `--archive-dir=<real>` (assert via a real
fixture dir so the difference is observable — my probe had to use one);
duplicate flags last-wins; `--freshen true` stray-token tolerated; `health
--dest --label` rc1 with `Unknown option: --label` (dash-leading value not
consumed). Each row is one `assert` — cheap, and each is exactly the kind of
row an Effect parser silently changes.

**G4 — completion (largest outright hole).**
`test_complete_generates_scripts_for_all_shells`: for each of
`bash zsh fish powershell`: rc0, stdout non-empty, stderr empty, stdout
contains `repo_jj_archive`; plus `bash -n <(runner complete bash)` syntax
smoke, and `complete bogus` + `complete` no-arg pinned to their chosen
post-migration behavior. The README advertises this command; nothing tests it.

**G5 — direct standalone bundle execution.**
`test_direct_bundle_execution_outside_project`: copy **only**
`archive/repo-jj-archive.mjs` into scratch (no launcher, no source), run via
shebang and via `node`, `refresh --json` a fixture → one JSON line, `.jj`
created. Complements the existing launcher test; catches
bundle-only-regressions the launcher path masks.

**G6 — launcher prefers source when deps present (the lockstep guard).**
`test_launcher_prefers_source_when_deps_present`: temp tree with launcher +
**real** source + `node_modules/gunshi` + `node_modules/@gunshi/plugin-completion`
dirs + **poisoned** bundle (`throw Error(...)`) → rc0. This is the mirror of
the existing poisoned-source test and is the one that fails when someone
migrates the source to Effect but forgets matrix row 2.

**G7 — launcher dep-check derives from actual imports.**
`test_launcher_source_gate_covers_every_bare_import` (unit-style, no
fixtures): parse bare imports of `archive/src/repo-jj-archive.ts`; assert each
top-level package appears in `script/repo-jj-archive.ts`'s `sourceFiles`
list. Future-proof: survives the Effect dependency set replacing gunshi
without test edits.

**G8 — bundle self-containment + shape.**
`test_bundle_is_self_contained`: static scan of
`archive/repo-jj-archive.mjs` — first line is the shebang; every `from "…"`
specifier matches `^node:`; no dynamic `import(`; `export { main }` present;
file mode executable. (rg-able in a few lines of Python.)

**G9 — bundle freshness vs rebuild.**
`test_committed_bundle_matches_source_rebuild`: build to a scratch outDir
rather than mutating `archive/` — e.g. `vp pack` with an overridden
output/config if vite-plus supports it, else a doc'd pre-merge step
`pnpm build && jj diff --stat` cleanliness. Needs a small build-tooling check
before it can be a test; listed as M-acceptance until then.

**G10 — argument-value validation messages.**
`test_refresh_argument_validation`: `--update maybe` → rc1, empty stdout,
stderr contains `invalid choice: 'maybe'`; `--depth 0` → `GIT_DEPTH must be
positive`; `--submodules` on existing archive → `requires explicit submodule
safety handling`; `--remotes 'not-json'` rc1 + empty stdout; `--remotes '[]'`
→ `JSON object`. All verified behaviors today, none under test.

**G11 — `--branch branch@remote` remote selection.**
`test_refresh_branch_at_remote_selects_declared_remote`: two-remote fixture,
`--branch main@<peer>` refreshes from peer. Framework-agnostic refresh
contract currently untested; include it because the translation loop sits
right next to it and is being rewritten.

Non-pytest acceptance checks for the migration PR itself: run the suite once
under the Node floor (`mise exec node@20.19 -- python3 -m pytest …`); manual
SIGINT/SIGTERM probe of the Effect binary mid-`refresh` (stdout stays clean);
`tasks/compfuzor/repo_jj_archive.tasks` diff is empty.

## Deliberate decisions this matrix forces

1. **Root `--version`**: keep the accidental hijack (and pin it), or make it
   print `0.1.0`. Affects `cli()` pre-pass ordering.
2. **Validation-error style**: keep single-line aggregation or adopt Effect's
   structured output; rc1 + empty stdout either way.
3. **`complete bogus` / `complete` no-arg**: silent rc0 + `:4` oddity — pin as
   compatibility or fix and test the fixed behavior.
4. **Completion implementation** with Gunshi gone: this is the one command
   with no library-neutral semantics to inherit; pick the generator before
   porting (row 12).
5. **Version constant**: `0.1.0` lives only inside the CLI entries while
   `package.json` says `1.0.0`; decide whether the Effect port reads it from
   one place.

## Cross-references

- [`archive/README.md`](/archive/README.md): the operator-facing contract
  (one-JSON-line rule, launcher resolution order, `--version` mapping note)
  this matrix formalizes.
- [`tests/integration/repo_jj_archive.test.py`](/tests/integration/repo_jj_archive.test.py):
  the 14-test baseline; rows 1–6 of the matrix exist only because its stderr
  assertions pin diagnostic strings.
- [`tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks):
  the framework-blind consumer; its `rc == 0` gate before `from_json` is the
  reason stdout purity is a hard invariant, not a niceness.
- [`design/repo-jj-archive/draft1.gpt6sol.md`](/design/repo-jj-archive/draft1.gpt6sol.md)
  and [`index.md`](/design/repo-jj-archive/index.md): toolkit design history
  explaining why the launcher prefers source first ("no bundler transport
  between checkout and execution") — a principle the Effect migration should
  keep, not regress into bundle-always.
- [`design/archive-migration/brief0.gpt6sol.md`](/design/archive-migration/brief0.gpt6sol.md):
  the `adopt`/`verify-adoption` custody brief; its "Source CLI and committed
  bundle through unchanged launcher" fixture row (§Verification) is the
  consumer of G5/G6 once those commands exist.
- [`design/repo-jj-archive/scaffold0.glm53max.md`](/design/repo-jj-archive/scaffold0.glm53max.md):
  scaffold record for the source-first launcher + committed bundle pairing
  under migration here.
