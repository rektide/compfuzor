# archive — jj archive tooling

Tooling for the canonical source archives at `~/archive/<org>/<repo>` — the
house convention for third-party and first-party checkouts that deployments
link into rather than re-clone. `dl` (the shell helper that fetches repos and
wikis into `~/archive`) is the primary user of the convention today; compfuzor
is leaning in via its `ARCHIVE_DOWNLOAD` lane, and this project is where that
shared tooling lives.

**Status: faithful scaffold — toolkit rework planned.** The runner was moved
here verbatim from `script/repo-jj-archive.ts` to establish the project shape.
Growing it into a general jj toolkit (workspaces, per-bookmark sync, push) is
planned; see [`design/repo-jj-archive/`](/design/repo-jj-archive/) (subsystem
design and the ghost-head incident) and
[`design/archive-deployment-premise/`](/design/archive-deployment-premise/)
(the direction the rework heads toward).

## Layout

| Path | What |
|---|---|
| `src/repo-jj-archive.ts` | The runner. Single-file TypeScript, executed directly by Node (type stripping). Exports `main()` and self-runs only as the main module. |
| `repo-jj-archive.mjs` | Committed build output (`pnpm build`), mirroring the [`runtime/`](/runtime) precedent. A deployment convenience, not a development artifact. |
| [`/script/repo-jj-archive.ts`](/script/repo-jj-archive.ts) | Thin compatibility launcher kept for the Ansible entry point. |

## Running from a checkout

```
node archive/src/repo-jj-archive.ts --help
```

The runner refreshes a jj-colocated archive without Git's worktree-resetting
update path: it snapshots the working copy into `harvest/<label>/…` bookmarks,
untracks local bookmarks, fetches declared remotes (with unreachable-commit
abandonment disabled), force-moves the base bookmark to the selected remote
tip with an off-ramp harvest for diverged history, and reconciles `@`. Stdout
is one JSON line — `{"changed": …, "notices": […]}` — for Ansible; diagnostics
go to stderr. Read the source header and the design docs before changing the
safety ordering.

## How Ansible invokes it

[`tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)
runs:

```
COMPFUZOR_REPO_JJ_RUNNER | default(playbook_dir ~ '/script/repo-jj-archive.ts')
```

so the default entry is the launcher at `script/repo-jj-archive.ts`, which
resolves in order:

1. `archive/src/repo-jj-archive.ts` — the TypeScript source directly via Node
   type stripping (preferred: no bundler transport between checkout and
   execution);
2. `archive/repo-jj-archive.mjs` — the committed bundle, for trees that ship
   only built output.

Override `COMPFUZOR_REPO_JJ_RUNNER` (as `tests/integration/repo_jj_archive.test.py`
does) to point at either the source, the launcher, or the bundle explicitly.

## Building

```
pnpm build
```

The root `vite.config.ts` packs `src/repo-jj-archive.ts` into
`repo-jj-archive.mjs` (ESM, node platform, no hashes/sourcemaps/dts, `clean:
false` so the source and this README survive). The bundle is committed like
`runtime/` so Ansible consumers work without a build step — rebuild and commit
when the source changes.

## Checks

`pnpm check` (format + lint + typecheck) covers `archive/src` via the root
globs; `archive/src/**/*.ts` is in `tsconfig.json`.
