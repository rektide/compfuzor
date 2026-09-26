---
type: Inquiry
title: block-in-file wishlist from apt-srctools scheme maintenance
description: Experiment-derived gaps in block-in-file for maintaining exactly one existing row via markers, probed against deployed v1.0.0.
status: draft
generated: { by: agent:glm53m, at: 2026-09-26 }
verified: { by: none, at: null }
sources:
  - id: bif-repo
    resource: ~/src/block-in-file
    title: block-in-file checkout (v1.0.0, cc221fd)
  - id: apt-srctools
    resource: /files/apt-srctools/apt-src-scheme.ts
    title: the consumer of these behaviors
---

# block-in-file wishlist

`apt-src-scheme.ts` needs exactly one thing from block-in-file (BIF):
**maintain exactly one existing row of a config file, with markers above and
below it.** The markers must be whole-line comments — legal in both apt
sources formats, including *inside* a deb822 stanza (verified with
`apt-get indextargets`; blank lines split stanzas and make apt reject the
file, comments do not). Everything below was probed against the deployed
binary (`command -v block-in-file` → v1.0.0, built from ~/src/block-in-file
at `cc221fd`), with transcripts under
[`.test-agent/apt-srctools/bif-lab/`](/test-agent/apt-srctools/bif-lab).

A material caveat up front: **the deployed 1.0.0 does not match the upstream
README's examples.** The README shows blank lines padding every inserted
block; the deployed binary never pads on insert (`--before`/`--after`/anchor)
or update. That skew matters because padding is the one behavior that would
be fatal for deb822. Either the README describes an older/newer deno build,
or the dist bundle diverged; pinning which is canonical would help consumers
reason about safety.

## What BIF already handles fine

- **Updating an existing block in place, tightly.** Given markers
  `# scheme-2 start` / `# scheme-2 end` around a row (even hand-inserted),
  `printf '<new row>' | block-in-file f --name scheme-2 --comment '#'`
  replaces the content between them without moving the block and without
  adding blank lines. This is the core "maintain one row" operation, and it
  works in both formats; apt re-reads the updated URI happily.
- **Marker syntax control.** `--comment '#' --name <name> --marker-start
  begin --marker-end end` produces exactly `# <name> begin` / `# <name> end`.
  Multi-word markers and hyphenated names work.
- **Anchoring an insert next to a row.** `--before '^URIs: '` inserts a
  block immediately above the matched line, tight (no padding).
- **Multiple named blocks in one file.** Distinct `--name`s coexist and
  update independently; `--mode ensure` is a true no-op when content is
  unchanged (mtime preserved), and `--read` gives a byte-exact drift check
  that exits 1 when the block is missing.

## Wishlist

### 1. Adopt an existing line into a managed block in place

- **Attempted** (wrap the live `deb ...` row by asking BIF to manage that
  content before it):
  `printf 'deb [ arch=amd64 ] https://example.com/debian stable main\n' | block-in-file b1.list --name scheme-1 --comment '#' --before '^deb '`
- **Happened**: BIF inserted a *copy* of the row (plus a provenance comment)
  above the original. The file then had the URI twice — active duplicate
  lines in classic, duplicate `URIs:` fields in a deb822 stanza. apt happens
  to tolerate both, but every later update edits the copy while the stale
  original row lives on forever.
- **Wish**: an adoption mode, e.g. `--adopt '^deb '` (or `--wrap-existing`):
  find the first line matching the regex, wrap it with this block's markers,
  and treat it as the block content from then on — a one-shot transition that
  an idempotent rerun recognizes as already-done. `apt-src-scheme.ts`
  currently does this surgery by hand and only hands the row to BIF afterwards.

### 2. Fail-closed update when the block is missing

- **Attempted**: `printf 'deb x\n' | block-in-file c7.list --name nosuch --comment '#' --create false`
- **Happened**: rc 0 and the block was **inserted at EOF anyway**. `--create
  false` did not gate block creation (nor file creation: pointing at a
  nonexistent directory also exits 0 silently). A maintenance tool that
  expects to update row N and instead appends a stray block at EOF has
  corrupted deb822 files in one more way: the appended block runs tight
  against the last stanza, and since comment lines do not end a stanza, its
  fields merge into that stanza.
- **Wish**: make `--create false` (or a new `--must-exist`) mean "update
  only; exit nonzero if the named block is absent", and error (not exit 0)
  when the target file is missing in update mode.

### 3. Suppress (or stabilize) the provenance comment

- **Attempted**: every insert/update; e.g. the c2 experiment ended with
  ```
  # scheme-1 start
  # source: <STDIN>
  URIs: http://downloads.cursor.com/aptrepo
  # scheme-1 end
  ```
- **Happened**: BIF injects `# source: <STDIN>` inside the block on each
  write. It is a legal comment in both formats, so nothing breaks — but it
  is noise in files humans read, it appears *between* the marker and the row
  (so "block content" is no longer exactly the row), and `<STDIN>` carries
  no information for a pipe-driven caller.
- **Wish**: a `--no-provenance` flag, or honoring `-i FILE`/`--source-label
  <text>` to make the line stable or absent, so block content stays exactly
  the managed row and `--read` output stays comparable to the intended row.

### 4. Format awareness for stanza-delimited files (deb822 et al.)

- **Attempted**: `--append-newline` inside a stanza
  (`--before '^Suites:'` on a copy of cursor.sources), and a default
  (no anchor) insert into a two-stanza `.sources` file.
- **Happened**: `--append-newline` added a blank line after the end marker —
  mid-stanza, which splits the stanza and makes apt reject the file
  (`E: Malformed entry ... (URI)`). The default insert appended at EOF
  tight against the last stanza, merging the new block's fields into it.
  (Per the README, upstream inserts pad with blank lines on both sides —
  the same corruption through the opposite default.)
- **Wish**: at minimum, documentation of these hazards for RFC822-style
  formats. Better: a `--blank-lines never|separators` mode (never emit blank
  lines inside or adjacent to the block; treat existing blank lines as
  stanza separators when scanning), so BIF can safely maintain a field row
  inside a stanza. With adoption (#1) and this, `apt-src-scheme.ts` could
  drop its surgical path entirely.

### 5. Per-row naming derived from position or content

- **Attempted**: maintain N rows in one file with generated names
  (`apt-scheme-1`..`apt-scheme-N`, next id = max existing + 1).
- **Happened**: it works, but the names are positional bookkeeping the
  caller must thread: if a human inserts a row between two managed ones, the
  numbering no longer matches reality, and a name reused by mistake creates
  two blocks with the same name — after which updates to that name **fail
  with rc 1** (verified in b6.list) with no pointer to which blocks
  collided.
- **Wish**: (a) accept a regex anchor as the block's identity —
  `--name 'cursor-uris' --anchor-regex '^URIs:'` meaning "the block whose
  content matches", making names self-describing; (b) when duplicate names
  collide, list the offending marker line numbers in the error.

## Not requested (for the record)

Blank-line padding control beyond #4, tag/timestamp machinery, envsubst,
DOS endings, chattr attributes, and `--additive` merging were not exercised:
none of them bear on "maintain exactly one existing row". The removal family
(`--remove`, `--remove-orphans`) was not needed because apt-srctools never
removes rows.

## Addendum: status and settled intent (2026-09-26)

Post-wave update after discussion with rektide; supersedes parts of the
numbered items above where noted.

**#1 adoption and #2 fail-closed: implemented and closed** in
block-in-file as bd tickets `bif-adopt-line` (`--adopt REGEX`) and
`bif-create-false-gates` (`--create false` now errors without writing when
the block or file is absent — a bugfix per the README's documented meaning).
Verified from repo source against a live deb822 fixture; the *deployed*
compfuzor standalone is still v1.0.0 and predates both — rebuild/redeploy is
gated until all BIF work lands, then apt-src-scheme.ts drops its surgical
adoption path (keeping verification + fallback).

**#3 provenance: settled as a two-stage `--source-label` ticket pair.**
Preliminary: `--source-label <text>` sets the provenance line's value —
semi-free-form and opaque to BIF, with an encouraged convention of a
path/glob that materially identifies the managing source (e.g.
`files/apt-srctools/apt-src-scheme.ts`); unset keeps today's default.
Batched later: `--source-label none|false` omits the line entirely. No short
aliases; marker-tag relocation considered and deliberately deferred. Intent:
provenance exists to help operators tell what manages a row and where to go
change it.

**#4 blank lines: settled as `--blank-lines keep|never|separators`,
default `keep`**, with per-regime semantics: adopt/update-in-place and
anchored inserts preserve surrounding context byte-for-byte under `keep`
(the new `--adopt` makes this the natural default); `never` is a hard
no-emitted-blanks guarantee for mid-stanza maintainers; `separators` makes a
fresh unanchored (EOF) insert ensure exactly one blank line before its begin
marker. Caveat carried on the ticket: under `keep`, unanchored inserts into
stanza formats still risk merging into a trailing stanza — that regime
remains caller responsibility unless `separators` is chosen.

**#5 (block identity): untouched, planned as a joint session.**

**Symlinks:** a separate research proposal landed at
`~/src/block-in-file/.design/symlinks/draft.gpt-6-sol.md` (recommending
`--symlink=follow` default with explicit `replace`/`error`, realpath before
all writes, backups beside the referent); the `bif-symlinks` ticket now
carries its pointer and the source corrections it found. Consumer-side,
apt-src-scheme.ts already defaults to skipping symlinks and realpaths under
`--follow`.

**Sequencing gate:** #5 joint session -> batch-file the #3 pair, #4, and
whatever #5 and the symlink proposal yield -> one sol-medium implements ->
rebuild/redeploy BIF -> rewire apt-src-scheme.ts onto `--adopt`.
