---
type: Design
title: archive/ scaffold — faithful move of repo-jj-archive into a top-level project
description: Stage one of the archive toolkit plan; the runner moved verbatim from script/ with a launcher shim, vite-plus bundle committed, and no functional rework.
resource: /design/repo-jj-archive/scaffold0.glm53max.md
tags: [compfuzor, archive, jj, repo, scaffold]
status: stable
generated: { by: model:glm53max, at: 2026-09-27 }
verified: { by: human:rektide, at: pending }
sources:
  - id: runner
    resource: /archive/src/repo-jj-archive.ts
    title: moved runner (verbatim)
  - id: launcher
    resource: /script/repo-jj-archive.ts
    title: compatibility launcher
  - id: subsystem-draft
    resource: /design/repo-jj-archive/draft0.gpt6sol.md
    title: subsystem design draft
  - id: premise
    resource: /design/archive-deployment-premise/draft0.glm53.md
    title: deployment premise the toolkit rework heads toward
---

# archive/ scaffold (2026-09-27)

What was done, so the toolkit rework agent knows the exact shape it inherits.
This stage deliberately changed **no behavior**: no splitting, no flag changes,
no gunshi/subcommands, no workspace or sync logic.

## Layout

```
archive/
  src/repo-jj-archive.ts    the runner, verbatim from script/ (see deltas)
  repo-jj-archive.mjs       committed vp pack output (runtime/ precedent)
  README.md                 what/why, invocation, ansible contract, build
script/repo-jj-archive.ts   thin launcher (ansible + tests still point here)
```

## Deltas from the original runner (the complete list)

1. `export` on `main()` — required so the launcher's dynamic import can invoke
   it; import stays side-effect-free.
2. Main-module guard per AGENTS.md cli rules replaces the unconditional
   `main().catch()` tail: `realpath(process.argv[1])` vs `import.meta.filename`
   compared inside a non-blocking `.then(onFulfilled, onRejected)` (rejection
   handler added to satisfy oxlint `no-floating-promises`; error format
   identical to the original catch).
3. `realpath` added to the `node:fs/promises` import.
4. `vp fmt` style (semicolons, one ternary rewrap) — required once
   `archive/src` entered the check globs; zero behavior change.

## Dual-path contract

- `tasks/compfuzor/repo_jj_archive.tasks` default remains
  `playbook_dir ~ '/script/repo-jj-archive.ts'`; `COMPFUZOR_REPO_JJ_RUNNER`
  still overrides.
- Launcher resolution: `archive/src/repo-jj-archive.ts` via type stripping
  first; `archive/repo-jj-archive.mjs` when src is absent. Verified by hiding
   `archive/src` temporarily.
- `tests/integration/repo_jj_archive.test.py` (RUNNER = script/ path) passes
  8/8, including the ansible plays that consume the JSON contract.

## Deliberately NOT done

- No gunshi/CLI framework, no subcommands, no config surface.
- No workspace lifecycle, per-bookmark sync, or push phase (the premise doc's
  direction) — that is the rework agent's mission.
- No `archive/` package.json/tsconfig of its own; the root project covers
  `archive/src` in tsconfig include, vp fmt/lint globs, and the vp pack array.
- tsconfig `script/repo-jj-archive.ts` entry replaced (per instructions), so
  the **launcher is no longer type-checked** — known tension, see below.

## Notes/tensions for the rework agent

- The launcher's `import.meta.filename` guard means symlinked invocation of
  `script/repo-jj-archive.ts` will not fire (same is true of the runner and
  the runtime precedent). Ansible/tests invoke by real path, so this is
  inert today.
- `archive/repo-jj-archive.mjs` output dir is `archive/` itself with
  `clean: false`; a future `archive/dist/` split is easy if the project grows
  non-bundle files, but today the runtime/ precedent (bundle beside sources)
  reads cleaner.
- The launcher is ~30 lines of untyped-checked glue; first rework move could
  be adding it (or its successor) back into a checked surface.
- Bundle rebuilds are deterministic (rebuilding left `runtime/compfuzor-runtime.mjs`
  byte-identical), so committing build output stays low-friction.
