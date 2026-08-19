---
type: Prompt # kind of knowledge (open-ended)
title: link-script quest prompt # display name
description: Prompt for designing deferred LINKS generation + file-entry link fields in compfuzor
tags: [compfuzor, design, links, systemd]
status: draft
generated: { by: llm:opencode, at: 2026-08-19T12:40:00-04:00 }
---

# prompt0: deferred LINKS + per-entry link fields — the quest

## situation

compfuzor's `LINKS` are executed at playbook runtime: the fs tasks create
each symlink immediately as the play runs. That couples "what links exist"
(data) to "when they're created" (execution), which fights two patterns we
keep hitting:

1. **install-script composition.** BINS scripts (`install-user.sh` etc.)
   are composed and run per-user at activation time. Links that should be
   established *then* — user-scope symlinks into `~/.local/bin`, the
   symlink farm for config overrides — can't ride that mechanism today
   because LINKS already ran at deploy time, as the deploying user.
2. **symlink ergonomics.** LINKS entries are their own top-level
   vocabulary; for one extra link you write a whole LINKS block. We want
   per-file annotations instead: `ETC_FILES`/`VAR_FILES` entries gaining
   e.g. `link:` / `link: user` fields that *generate* the LINKS entry, the
   way `destTemplate` and friends already extend file entries.

## the quest

Design both, together, because they share a backbone:

- **record the data, act at runtime.** LINKS (and generated link fields)
   become data recorded into the deploy (an `install-links.sh` composed
   into BINS, likely with scopes) instead of a deploy-time side effect.
- **per-entry link generation.** A file entry says where it should also be
   linked; the LINKS entry gets written for it. `link: user` marks
   user-scope links — deferred to install-user composition, `${HOME}`
   relative, no sudo.
- **general system health.** While in here: scope handling for links
   (system vs user), bypass flags (`LINKS_BYPASS` exists — how does it
   interact with a script?), interplay with the fsh lookup's `home='%h'`
   / `'${HOME}'` composition, and whether the symlink farm in watchman's
   `install-user-etc.sh` should become the first consumer of the generic
   mechanism instead of bespoke shell.

## starting points (verified in tree)

- `LINKS` normalization: `tasks/compfuzor/vars_base.tasks:144-147`
  (dict → items, `dest`/`src`).
- Execution-time linking: `tasks/compfuzor/fs_hierarchy.tasks` /
  `compfuzor.includes` LINKS loop (see bypass wiring there).
- File-entry extension precedent: `destTemplate` on ETC_FILES
  (`vars/common.yaml` readme subsystem), `basedir` on BINS.
- Scope precedent: BINS `scope: user` composition into
  `install-user.sh` (`bin_composers.py`).
- fsh composition params: `library/lookup_plugins/fsh.py`
  (`home='%h'`, `home='${HOME}'`).
- Watchman's bespoke farm: `watchman.srv.pb` `install-user-etc.sh`.

## research prompt (for the wave)

> Investigate compfuzor's LINKS pipeline end to end: normalization in
> vars_base.tasks, execution in the fs tasks and compfuzor.includes,
> LINKS_BYPASS semantics, and how BINS gain scope + composition
> (bin_composers.py, gen_bins.tasks). Then propose a design where (a)
> LINKS are recorded as data and materialized by a composed
> `install-links.sh` at install time (system and user scopes), and (b)
> file entries (ETC_FILES/VAR_FILES/BINS) can declare `link:`/`link:
> user` fields that generate LINKS entries, mirroring destTemplate.
> Identify shared vocabulary with the fsh lookup's home=/runtime=
> parameters and how a generated link target like
> `~/.config/watchman-main/watchman.json` would be expressed for both
> system and user scope without per-user templating. Note general health
> issues found along the way.

## vectors from the user

- "record the data, then do it at runtime" — deferred execution is the
  core requirement, not optional.
- "LINKS are kind of a pain" — ergonomics matter; per-entry fields are
  wanted, top-level blocks are the pain point.
- "please be on the lookout for general system health improvements" —
  capture them, don't fix them silently.
- dovetails with the watchman hybrid deploy's symlink-farm need.
