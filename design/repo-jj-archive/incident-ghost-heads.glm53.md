---
type: Design
title: Ghost-head incident — jj view referencing objects pruned by git maintenance
description: repo_jj_archive failed on opencode.src.pb because the archive's jj view kept a bare head (and bookmark conflict terms) whose objects a git repack had pruned; every heads(all()) walk died with "Object … not found".
resource: /design/repo-jj-archive/incident-ghost-heads.glm53.md
tags: [compfuzor, archive, jj, repo, incident]
status: stable
generated: { by: model:glm53, at: 2026-09-27 }
verified: { by: human:rektide, at: 2026-09-27 }
sources:
  - id: runner
    resource: /script/repo-jj-archive.ts
    title: repo-jj-archive refresh runner (failing harvest heads(all()) walk)
  - id: archive
    resource: /vars/common.yaml
    title: ARCHIVE_DIR / ARCHIVE_SRC / ARCHIVE_DOWNLOAD
  - id: premise
    resource: /design/archive-deployment-premise/draft0.glm53.md
    title: archive deployment premise draft
  - id: subsystem-draft
    resource: /design/repo-jj-archive/draft0.gpt6sol.md
    title: repo-jj-archive design draft
---

# Ghost-head incident (2026-09-26, ~/archive/anomalyco/opencode)

## Failure

`opencode.src.pb` → [`repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)
failed in `harvest()`'s `jj log -G -r heads(all())` with:

```
Error: Unexpected error from commit backend
1: Object ad5e582efde039c34378a250cc8276c5c2874653 of type commit not found
```

The run died **before any fetch or bookmark rewrite** — the multi-upstream
convergence machinery was never reached. `jj status`, `bookmark list`, and
`log -r @` all succeed because none of them materialize view heads;
`heads(all())` is the first command that does.

## Root cause chain

1. **2026-09-22 08:22** — a fetch/force-move during early repo-jj-archive
   testing left commit `ad5e582` as a *bare view head*. jj deliberately keeps
   unreachable heads (and the runner pins `git.abandon-unreachable-commits=false`
   — the "rewritten upstream history stays reconstructible" policy).
2. Four conflicted bookmarks (`working-20260923`, `jj-vcs-20260903`,
   `jj-vcs-rektide-20260903-prefreshen`, `explicit-port-20260817`) additionally
   carried ghost terms in their conflict state.
3. **2026-09-22 18:52** — a git-side repack (502MB pack) pruned the now
   unreachable objects. **No git ref covered them**: `git fsck` stays 100%
   clean, `refs/jj/keep` only protects *visible heads at export time* — bare
   heads and conflict terms fall through that gap.
4. Result: jj's view + append-only index reference an object absent from the
   odb. Every revset that materializes all view heads dies. The repo was
   silently broken for four days; the nightly refresh was simply the first
   `heads(all())` walker.

Diagnostic trap: piping `jj log -r 'heads(all())'` into `head -N` SIGPIPEs jj
*before* it reaches the ghost — the command can look like it succeeds.

## Remedy applied

1. Resolved each conflicted bookmark by `jj bookmark set` to the value every
   real side already agreed on (drops ghost terms from the view).
2. Pinned the parked `@` under `parked-20260926` (real ref).
3. Re-adopted: `mv .jj .jj.broken-ghost-20260926 && jj git init --colocate` —
   fresh jj state imported from the fsck-clean git refs. All bookmarks,
   remotes, and history that actually exists come back; the op log is
   sacrificed (preserved in the `.jj.broken-ghost-20260926` backup).
4. Verified end-to-end: the exact failing argv returns
   `{"changed":true,...}` and the harvest flow works.

## Lessons for the subsystem

- The reconstructibility policy is **unenforced against git maintenance**:
  anything running `git gc`/repack can delete exactly the unreachable commits
  jj is retaining. Candidate mitigations: pin `gc.auto=0` in archive repos at
  clone/adopt time; preflight `visible_heads()` materialization before any
  `all()`-walking step so the failure is diagnosable instead of cryptic;
  optionally a flag-gated re-adopt self-heal.
- Bare heads and conflicted-bookmark terms are the two carriers that slip past
  keep refs. Both are cheap to detect by materializing `visible_heads()`.

## Cross-references

- [`/design/repo-jj-archive/draft0.gpt6sol.md`](/design/repo-jj-archive/draft0.gpt6sol.md) — subsystem design draft this incident informs.
- [Toolkit follow-up](/design/repo-jj-archive/draft1.gpt6sol.md) — the landed `visible_heads()` preflight, explicit backup/re-adopt command, and fixture proof that address these lessons.
- [`/design/archive-deployment-premise/draft0.glm53.md`](/design/archive-deployment-premise/draft0.glm53.md) — the runner-on-main-working-copy premise under which the incident occurred.
