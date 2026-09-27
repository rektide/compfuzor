---
type: Design
title: From standalone checkout to archive-managed source — the dl migration
description: Fixture-tested manual adoption, safety gaps, and a proposed one-time archive adoption surface.
resource: /design/archive-migration/draft0.gpt6sol.md
tags: [compfuzor, archive, migration, jj, dl]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: toolkit
    resource: /archive/README.md
    title: Archive toolkit commands and safety contract
  - id: legacy-harvest
    resource: /script/harvest-legacy-repo.sh
    title: Cross-checkout Git harvest implementation
  - id: dl-playbook
    resource: /dl.src.pb
    title: dl archive deployment and global CLI link
  - id: toolkit-design
    resource: /design/repo-jj-archive/draft1.gpt6sol.md
    title: Composable archive toolkit design
  - id: deployment-premise
    resource: /design/archive-deployment-premise/draft0.glm53.md
    title: Archive main worktree versus deployment workspace
---

# From standalone checkout to archive-managed source

## What is up

Compfuzor already knows how to **refresh an archive** and how to **render a
deployment linked to it**. The operator's more fundamental use case is moving
the working repository *into* that arrangement: `~/src/dl` is a long-lived
standalone checkout, while [`dl.src.pb`](/dl.src.pb) wants canonical source at
`~/archive/rektide/dl`, a generated `~/src/dl-git/repo` symlink in user mode,
and a pnpm global `dl` shim pointing at the managed checkout. A clone of
`main` alone would lose the detached line, local branch tips, and dirty work;
merely installing the playbook would not transfer runtime databases or retire
the old checkout. This is an adoption problem, not another fetch mode.

Research question for the next slice: can the existing archive toolkit plus
the legacy-harvest script safely transfer *all declared source work*, expose
everything they intentionally leave behind, and make installation/retirement
separately verifiable? The answer today is **yes for Git-representable history,
with a careful human walkthrough; not yet as a trustworthy one-command
conversion**. The current archive already contains a prior `dl` harvest; the
commands below are a recipe for a not-yet-migrated checkout, **not instructions
to repeat this migration on the production paths**.

## Evidence: read-only specimen and an isolated migration

The real `~/src/dl` has detached `HEAD` at `c2ed963`, local `main` at
`e9c7c40`, Git remotes named `github` and `origin` (the latter points at
Tangled), and an untracked `.jj/` directory. `facts.db` and `wf.db` are Git
ignored; **some `.data/*.db-wal` and `.beads` files are tracked** and therefore
not protected by ignore rules. The generated pnpm shim currently executes
`~/src/dl/dl.ts`. Read-only inspection of `~/archive/rektide/dl` found
`harvest/dl-legacy/{main,head,working-copy}` and two safety bundles from an
earlier run; the `working-copy` tree contains `.jj` and `.data` at its root.
That evidence makes auditing existing recovery refs/bundles **before any push**
important; this draft neither removes nor republishes them. The existing
archive's declared `origin` is GitHub; it is *not* the legacy checkout's
`origin`. The choice of remote belongs to the deployment contract, not to
the incidental legacy remote name.

I exercised the **real** `archive/src/repo-jj-archive.ts` and
`script/harvest-legacy-repo.sh` in the ignored
`.test-agent/archive-migration/fixture-gpt6sol/` only. The fixture has a local
bare `file://` upstream with `main`; a separate legacy clone has one unpushed
commit on `main`, a later detached commit, a modified tracked README, an
untracked `notes.txt`, ignored `facts.db`/`wf.db`, and an untracked `.jj/`
*placeholder*. The placeholder tests the directory-selection hazard, **not**
successful export of a valid jj repository; `jj git export` warned and the
script continued. No production repository, global link or database was
changed for this test.

Reproduction outline (from the compfuzor checkout; commit identity/timestamps
will differ):

```sh
ROOT=$PWD
F="$ROOT/.test-agent/archive-migration/fixture-gpt6sol"
mkdir -p "$F"
git init --bare --initial-branch=main "$F/upstream.git"
git init --initial-branch=main "$F/seed"
git -C "$F/seed" config user.name Fixture
git -C "$F/seed" config user.email fixture@invalid
printf 'base\n' > "$F/seed/README.md"
printf 'facts.db\nwf.db\n' > "$F/seed/.gitignore"
git -C "$F/seed" add README.md .gitignore
git -C "$F/seed" commit -m base
git -C "$F/seed" remote add origin "file://$F/upstream.git"
git -C "$F/seed" push -u origin main
git clone "file://$F/upstream.git" "$F/legacy"
git -C "$F/legacy" config user.name Fixture
git -C "$F/legacy" config user.email fixture@invalid
printf 'legacy main\n' >> "$F/legacy/README.md"
git -C "$F/legacy" add README.md
git -C "$F/legacy" commit -m 'local main'
git -C "$F/legacy" switch --detach
printf 'detached head\n' > "$F/legacy/detached.txt"
git -C "$F/legacy" add detached.txt
git -C "$F/legacy" commit -m 'detached work'
printf 'uncommitted edit\n' >> "$F/legacy/README.md"
printf 'loose experiment\n' > "$F/legacy/notes.txt"
mkdir "$F/legacy/.jj"
printf 'metadata\n' > "$F/legacy/.jj/experimental"
printf 'runtime\n' > "$F/legacy/facts.db"
printf 'runtime\n' > "$F/legacy/wf.db"

CLI="$ROOT/archive/src/repo-jj-archive.ts"
node "$CLI" refresh --dest "$F/archive" --repo "file://$F/upstream.git" \
  --branch main --label fixture
node "$CLI" health --dest "$F/archive"
bash "$ROOT/script/harvest-legacy-repo.sh" "$F/legacy" "$F/archive" \
  --label fixture-legacy
node "$CLI" health --dest "$F/archive"
git -C "$F/archive" for-each-ref --format='%(refname:short) %(objectname:short)' \
  'refs/heads/harvest/fixture-legacy/*'
git -C "$F/archive" ls-tree -r --name-only \
  refs/heads/harvest/fixture-legacy/working-copy
```

Observed output: `refresh` said `Archive changed`, `cloned jj-colocated
archive`, `BOOKMARK CREATED main -> cbd7c816…`; both health checks said
`Visible heads OK; no conflicted bookmarks`. Harvest created `main` at
`07a42af…`, `head` at `ecd1781…`, and `working-copy` at `d686612…`; it also
warned that `jj git export` failed in the deliberately fake `.jj/`. The
synthetic working-copy tree was `.gitignore`, **`.jj/experimental`**, `README.md`,
`detached.txt`, `notes.txt`. Neither ignored database was present. The legacy
checkout still reported its original ` M README.md`, `?? .jj/`, and
`?? notes.txt`. The two `--all` bundles contained the pre-harvest Git refs
(including the legacy detached `HEAD`), **not the synthetic dirty worktree
commit made after bundling**. They cannot restore ignored runtime state.

I repeated the harvest with the **same** label after two seconds: `main` and
`head` reported `Everything up-to-date`; `working-copy` was force-updated from
`d686612…` to `3d496be…` **despite an identical tree**, and two more bundles
appeared. `health` still passed. An interrupted run or a successful retry is
therefore not a stable, append-only import operation. `refresh` after harvest
reported `Archive unchanged`, retained all three refs, and `health` passed;
the archive worktree remained clean.

Finally, I exercised a **safe-for-untracked-`.jj` invocation**, using only a
temporary per-invocation Git exclude file (not a change to the legacy repo):

```sh
printf '.jj/\n' > "$F/exclude-transient"
git -C "$F/legacy" -c "core.excludesFile=$F/exclude-transient" \
  check-ignore .jj/experimental facts.db wf.db
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile \
  GIT_CONFIG_VALUE_0="$F/exclude-transient" \
  bash "$ROOT/script/harvest-legacy-repo.sh" "$F/legacy" "$F/archive" \
    --label fixture-safe
git -C "$F/archive" ls-tree -r --name-only \
  refs/heads/harvest/fixture-safe/working-copy
```

This tree contained only `.gitignore`, `README.md`, `detached.txt`,
`notes.txt`; `.jj/` and both ignored DBs were absent. I separately tested the
operator's order on a **new** fixture archive:

```
refresh --dest "$F/staged/archive" --repo "file://$F/upstream.git" --label fixture --branch main --update false
health --dest "$F/staged/archive"
harvest-legacy-repo.sh "$F/legacy" "$F/staged/archive" --label fixture-safe  # with the same GIT_CONFIG_* exclusions
health --dest "$F/staged/archive"
refresh --dest "$F/staged/archive" --repo "file://$F/upstream.git" --label fixture --branch main
health --dest "$F/staged/archive"
```

With the actual `node "$CLI"`/`bash "$ROOT/script/…"` prefixes above, this
produced `Archive changed` (initial clone), then `Visible heads OK` throughout,
three imported refs, `Archive unchanged` on the final refresh, and a clean
archive worktree. Copying the fixture's ignored DBs into the archive and
running `node "$CLI" snapshot --dest "$F/archive"` left `git status --short`
empty: ignored state can live beside source without joining jj's snapshot.
That proves the *ignore behavior on this fixture*, not application-specific
database consistency or safety of copying live databases.

## Operator walkthrough: source, history, deployment, retirement

**For a new migration**, use the following as the README-worthy sequence.
For today's `dl`, the archive and recovery refs already exist: begin with
the inspection/verification steps, decide whether a corrected import under
a **new** label is needed, and never blindly rerun harvest into an existing
label. Substitute the actual repository URL selected by the playbook; do not
mirror `~/src/dl`'s `origin` into the archive merely because it is named
`origin`.

1. **Inventory and hold the old path steady.** Stop writers; record
   `git -C "$LEGACY" status --short`, `branch -vv`, `remote -v`,
   `rev-parse HEAD`, `stash list`, and tracked/untracked/ignored inventories
   (`ls-files -- .data .beads`, `ls-files --others --exclude-standard`,
   `status --short --ignored` selectively). Check `.jj/`, secrets and Git
   LFS/submodules separately. Audit any tracked database/WAL/credential
   material; Git excludes do **not** remove tracked files or existing history.
   For `dl` specifically, `.data/*.db-wal` and some `.beads` contents are
   tracked. Make a separate, access-controlled, consistent backup of any
   running database; Git bundles are not runtime backups. Do not push the
   recovery refs by default.

2. **Prepare the archive independently.** With
   `ROOT=/path/to/compfuzor`, `LEGACY="$HOME/src/dl"`,
   `ARCHIVE="$HOME/archive/rektide/dl"`, `LABEL=dl-legacy-safe1`, and
   `CLI="$ROOT/archive/src/repo-jj-archive.ts"`, first run
   `node "$CLI" health --dest "$ARCHIVE"` **if it exists**. Inspect the
   existing checkout, archive `main`, remotes and any `harvest/$LABEL/*` refs.
   On an absent archive only, run:

   ```sh
   node "$CLI" refresh --dest "$ARCHIVE" \
     --repo https://github.com/rektide/dl --branch main \
     --label dl-git --update false
   node "$CLI" health --dest "$ARCHIVE"
   ```

   On an existing archive, `refresh --update false` still snapshots its
   worktree and validates declared remotes; it does not mean read-only. A URL
   mismatch is a review gate: inspect the declared/actual table, then choose
   `remotes --reconcile` *only if deliberately changing that archive URL*.
   Do not enable `--reconcile-remotes` just to make the migration pass.

3. **Import recoverable source work, without importing untracked jj
   internals.** The existing shell script requires the destination checkout
   and writes sibling `*.bundle` backups, then sends each local branch,
   otherwise-uncontained detached/current `HEAD`, and a synthetic dirty-tree
   commit to `harvest/$LABEL/*`. Until it has an exclusion flag, the following
   *temporary* Git config is the tested workaround for an **untracked** `.jj/`:

   ```sh
   EXCLUDES=$(mktemp)
   printf '.jj/\n' > "$EXCLUDES" # audit other untracked transient paths too
   git -C "$LEGACY" -c "core.excludesFile=$EXCLUDES" \
     check-ignore .jj/repo/config-id facts.db wf.db
   GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile \
     GIT_CONFIG_VALUE_0="$EXCLUDES" \
     bash "$ROOT/script/harvest-legacy-repo.sh" \
       "$LEGACY" "$ARCHIVE" --label "$LABEL"
   ```

   This only affects ignored/untracked input; **do not interpret a successful
   exit as proof that all jj-only commits were exported**. The script currently
   logs an export failure as a warning and proceeds. If the old `.jj` is a
   functioning jj checkout, inspect and deliberately export/pin jj-only work
   before accepting the migration. Avoid name collisions: never reuse an
   already populated label for a corrective import; keep existing refs and
   bundles while deciding on cleanup. Bundles belong in private storage and
   should be verified and backed up independently before retiring the source.

4. **Verify Git material, not only CLI success.** Run `health` again and
   compare `git -C "$LEGACY" rev-parse HEAD` to
   `git -C "$ARCHIVE" rev-parse "refs/heads/harvest/$LABEL/head"` when HEAD
   is outside branch tips; compare each source branch SHA to its namespaced
   archive ref. Inspect
   `git -C "$ARCHIVE" ls-tree -r --name-only
   "refs/heads/harvest/$LABEL/working-copy"` for included and excluded paths;
   **fail the handoff on unexpected `.jj`, secrets, databases, or missing source
   files**. `git bundle list-heads` / `git bundle verify` validate the safety
   bundles, but neither captures ignored working state nor newly made
   synthetic commits; keep both the legacy path and the archive until the
   handoff is accepted. If source Git already contains private material in
   history, choosing whether to publish any refs is a separate policy
   decision. No automatic `--push` or wildcard push here.

5. **Select the deployment line deliberately.** Source preservation does not
   imply `main` contains the detached line: `dl.src.pb` requests `main`.
   Choose whether to keep `main` as the runnable program, integrate detached
   work explicitly, or make a future dedicated workspace/bookmark; do not
   silently move `main` to detached `HEAD`. When ready to fetch/reconcile the
   selected base, run
   `node "$CLI" refresh --dest "$ARCHIVE" --repo
   https://github.com/rektide/dl --label dl-git --branch main`, review notices,
   `health`, and worktree conflicts. The current runner may merge into the
   archive's **main worktree**; do not run it while another process edits that
   checkout.

6. **Move runtime use, then state, then the global entry point.** Only after
   repository checks, run the declared `USERMODE=True` playbook with the local
   connector: `ansible-playbook -i 'localhost,' -c local dl.src.pb -e
   USERMODE=True`. It creates `~/src/dl-git/repo` pointing at the archive and
   runs `pnpm install && pnpm link --global` from there. Confirm the link with
   `readlink -f "$HOME/src/dl-git/repo"`; `command -v dl` alone identifies
   only the pnpm shim, **not its target**. Inspect the generated shim and pnpm
   global link target, then exercise `dl --version` and a non-destructive
   command. Plan `.db`/WAL/state moves per application's locking and recovery
   rules *while the old writer is stopped*; a blind `cp` of a live SQLite
   database or `pnpm link` is not a state migration. Check the new ignored
   paths, permissions, and CLI behavior. If the link points to the wrong
   checkout, the reversible shim rollback is `cd "$LEGACY" && pnpm link
   --global` while the legacy path still exists.

7. **Retire, do not silently prune.** Confirm no service, shell script,
   symlink, pinned path, database user, or global shim still targets the old
   directory; verify backups and actual archive recovery refs. Keep the old
   checkout intact during a deliberate observation period, then manually
   rename/park it (and only later dispose of it under an explicit retention
   policy). Compfuzor does not delete undeclared files; generating a `repo`
   symlink is not authorization to delete `~/src/dl`.

## Command design: make adoption first-class without hiding the tail

The present `harvest` command pins a revision **already inside one jj repo**;
it cannot import another checkout. `refresh` can clone/adopt an existing
*destination* Git directory, but takes no `--legacy` path, does not inventory
ignored state, and intentionally does not install software or retire source
paths. The shell script crosses repositories using Git push to local refs and
`commit-tree`; it has neither plan/report mode nor robust skip/retry behavior.
Putting cross-checkout import into `refresh` would blur steady-state
convergence with a one-time custody transfer. Proposed surface:

```text
archive adopt --legacy DIR --dest DIR --repo URL --branch main \
  --label dl-legacy --exclude-from FILE [--plan | --apply] [--json]
archive adopt verify --legacy DIR --dest DIR --label dl-legacy [--json]
```

`adopt` plans by default; `--apply` is an explicit transfer of **source
history and declared dirty source files**, never a retirement/pnpm/database
operation. Its preflight should validate two distinct realpaths, a cleanly
identifiable Git repository on each side, URL policy, Git/JJ health,
submodules/LFS, writeability and local backup space. If destination is absent,
compose the existing clone/adopt behavior with `update=false` before import;
if present, never substitute its `origin` from the source checkout. Include a
before/after manifest of source branch names and OIDs, detached `HEAD`,
working-tree parent/tree identity, selected ignored/untracked and tracked
runtime-like paths, destination refs, bundle paths and verification result.
Report **which data was intentionally *not* moved**; do not leak ignored-file
contents into JSON/logs. Surface jj-only revisions as a blocking condition
unless explicitly and successfully exported/pinned. The tool should refuse
potential secrets under source Git history before *publishing*; local import
and remote publication are separate permissions.

Implement cross-repo import as its own `import-legacy` unit under `adopt`, not
as another meaning of existing `harvest`. Once a transaction succeeds,
re-running against the same source state should report unchanged: a stable
`harvest/<validated-label>/<branch|head|working-copy>` ref may only be reused
when the OID/content identity matches; differing source work creates a **new,
append-only** recovery name (e.g. `working-copy-<parent>-<tree>`) or asks for
an explicit new label, never `git push +` over a recovery ref. Check for a
preexisting namespace **before** writing either bundle or ref. Snapshot the
dirty tree deterministically (parent + tree; staged/unstaged distinctions
reported but not silently equated to a Git commit); treat `git add` errors as
fatal, rather than `|| true`. First make private, collision-resistant bundles
and record checksums, then ensure all pinned objects are covered by a
**post-import** backup as well: pre-harvest `--all` bundles do not back up the
new synthetic worktree commit. Git safety bundles do not back up valid jj-only
state, ignored databases, or the old `.jj` op log.

Exclusion defaults must be scoped and reviewable: never harvest `.git`/`.jj`
internals into a working-copy commit; report them separately as custody
metadata, **not** as source code. Respect `.gitignore`, accept an explicit
`--exclude-from`, show tracked exceptions that exclusions cannot hide, and
stop if the proposed tree includes unexplained private/transient files.
Don't unilaterally drop `.beads` or other user content: inspect tracked status
and explain the tradeoff between preserving source provenance and publishing
runtime state. Prefer an intentional manifest over a hardcoded universal
database blacklist. Retain the shell script as a marked low-level escape hatch
until a tested replacement exists; do not silently change its meaning beneath
existing users. `verify` should compare source fingerprints and archive refs,
inspect the working-copy tree/exclusions, validate bundles, and report a
**retirement preflight**: outstanding jj-only revisions, ignored state,
unmoved files, active path consumers/shim target, worktree conflicts, and
missing off-host backup as unresolved items, **not** execute deletion. An
interrupted `adopt` resumes by comparing evidence rather than resetting the
archive. Keep repo source transfer usable without Ansible; expose the playbook
and state/shim tasks as human follow-ups, not forced adoption side effects.

### Tradeoffs and open questions

- How should a valid legacy `.jj` be handled when `jj git export` has
  unexportable/conflicted heads? Treating a warning as success loses work;
  copying `.jj` into Git is worse. Is blocking until an operator pins/resolves
  all jj-only commits the acceptable default?
- Which `dl` state is truly part of source versus runtime? The real checkout
  already tracks `.data/*.db-wal` and some `.beads` paths; an ignore-only rule
  cannot undo that history. Does publication require a history/privacy review,
  and who owns consistent DB backup and restoration?
- Should a migration choose a **deployment workspace** now, or preserve the
  current main-worktree symlink contract while designing workspaces separately?
  Adoption should not bake in the existing main-worktree surprise.
- What are the acceptable guarantees for backup custody and retries: local
  bundles plus source retention, or a verified independent/off-host copy
  before retiring legacy? Should an unchanged retry require the same label and
  source path fingerprint, or permit renames?
- Who decides whether detached `HEAD` is runnable, forked experimentation, or
  the new selected base? Neither migration nor `GIT_VERSION: main` should make
  that judgment implicitly. When is an opt-in publish of audited recovery
  refs appropriate, and to which remote (GitHub vs Tangled)?

## Cross-references

- [`archive/README.md`](/archive/README.md) and [toolkit implementation](/archive/src/refresh.ts) define `health`, `refresh`, remote mismatch and main-worktree reconciliation; adoption composes but must not quietly extend their routine semantics.
- [`script/harvest-legacy-repo.sh`](/script/harvest-legacy-repo.sh) is the existing two-checkout transport; its initial bundles, forced refs, working-copy temp index, and ignored-export-error path are the fixture's specific safety findings.
- [`dl.src.pb`](/dl.src.pb), [`vars/common.yaml`](/vars/common.yaml), and [`fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks) establish the source/deployment paths and the separate pnpm global shim tail.
- [Original archive safety contract](/design/repo-jj-archive/draft0.gpt6sol.md) explains why `refresh` snapshots/harvests before fetch; this is different from importing another repository's history.
- [Toolkit follow-up](/design/repo-jj-archive/draft1.gpt6sol.md) documents landed subcommands and explicit re-adoption; [the ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md) shows why recoverability requires actual Git ref/object coverage, not only a jj view head.
- [Archive scaffold](/design/repo-jj-archive/scaffold0.glm53max.md) describes the CLI/Ansible launcher split; an `adopt` command would also need both source and committed bundle updated when implemented.
- [Deployment premise](/design/archive-deployment-premise/draft0.glm53.md) argues for workspace-per-deployment and per-bookmark decisions; a one-time migration should not accidentally decide that larger destination architecture.
