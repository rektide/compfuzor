---
type: Design
title: apt-srctools design
description: Canonical JSON model, format fidelity map, CLI surfaces, and the block-in-file scheme strategy for the apt sources.list manipulation tools.
status: draft
generated: { by: agent:glm53m, at: 2026-09-26 }
verified: { by: none, at: null }
sources:
  - id: playbook
    resource: /apt-srctools.etc.pb
    title: the deployment contract (bin names, README blurb, FUTURE pin tool)
  - id: apt-lane
    resource: /doc/apt.md
    title: the deb822 authoring lane (APT/APTS) these tools sit beside
  - id: apt-manual
    resource: https://manpages.debian.org/apt/sources.list.5.en.html
    title: sources.list(5), both formats and embedded Signed-By
---

# apt-srctools design

Compfuzor's apt story has two lanes: the **authoring lane**
([`doc/apt.md`](/doc/apt.md)) declares sources as `APT:`/`APTS:` deb822
maps rendered by the playbook, and the **legacy lane** still writes classic
`.list` lines from `APT_REPO`-era variables. What has been missing is a way
to work with the sources apt actually has on a host — files written by other
tools (cursor, google-chrome drop their own `.sources`), hand-edited lists,
and the mixed-format reality of a long-lived `/etc/apt/sources.list.d`. The
[playbook](/apt-srctools.etc.pb) deploys six zero-dependency TypeScript bins
sharing one canonical JSON model so that any format pair composes:
classic ↔ json and deb822 ↔ json, plus a directory converter and a scheme
flipper. JSON is the standard intermediate, not a side effect — the fidelity
contract below is the point of the design.

The tools are file-centric, not declaration-centric, deliberately: they
manipulate what exists rather than reconciling it (no pruning, no adoption of
foreign files beyond a single row at a time — see the scheme strategy). That
keeps them composable with the authoring lane, which keeps ownership of what
*should* exist.

## The JSON model

Every key is always present; `null` means absent. One classic line or one
deb822 stanza parses to one entry:

```json
{
  "sources": [
    {
      "types": ["deb"],
      "uris": ["https://deb.debian.org/debian"],
      "suites": ["forky"],
      "components": ["main", "contrib"],
      "signedBy": "/usr/share/keyrings/x.gpg",
      "architectures": ["amd64"],
      "trusted": false,
      "enabled": true,
      "options": {},
      "fields": {}
    }
  ]
}
```

- `types` — `deb` / `deb-src`. Classic lines carry one; deb822 `Types:` can
  carry several.
- `uris` / `suites` / `components` — arrays; flat repos are `suites:
  ["./"]` (or `["/"]`) with empty `components`, matching
  [doc/apt.md](/doc/apt.md)'s `Components: []` convention.
- `signedBy` — keyring path, fingerprint list, or a **verbatim PGP keyblock**
  (multi-line string). Keyblocks decode/encode via deb822 continuation space
  plus dot-stuffing (` .` for blank lines) per sources.list(5), the same
  rules the authoring lane's renderer uses.
- `architectures` — comma or space separated values normalize to arrays.
- `trusted` / `enabled` — booleans. Disabled classic rows (`#deb ...`) and
  `Enabled: no` stanzas both parse to `enabled: false`.
- `options` — the classic-side home for bracket options the model does not
  otherwise spell (`signed-by`/`arch`/`trusted` are lifted out; remainder
  like `lang`, `target` stay here verbatim).
- `fields` — the deb822-side home for fields the model does not spell
  (`By-Hash`, `X-Repolib-Name`, ...), values verbatim including
  continuations.

The two side-homes mirror each other through a fixed alias table
(`lang ↔ Languages`, `target ↔ Targets`, `pdiffs ↔ PDiffs`,
`by-hash ↔ By-Hash`) applied **at emission of the opposite format**, so a
value crosses formats without changing meaning even though its JSON home
differs by origin. Bracket option semantics follow apt exactly as probed:
options separate on whitespace only — `arch=amd64,i386` is one option with a
comma-bearing value, and a legacy blob like `trusted=yes,arch=amd64` is a
single `trusted` option whose trailing junk apt ignores (the blob roundtrips
verbatim through `options.trusted` / `Trusted:` rather than being silently
reinterpreted).

## Fidelity map

| Path | Guarantee |
| --- | --- |
| classic → json → classic | exact modulo whitespace, bracket spacing and option order; comments drop; commented-out rows keep `#` and trailing bytes |
| deb822 → json → deb822 | exact modulo field order, comments, and multi-value normalization to space-separated values |
| classic → json → deb822 | **semantically lossless**: one line stays one stanza (no deb/deb-src or same-repo merging); aliasable options become fields; anything without a deb822 spelling warns on stderr and drops |
| deb822 → json → classic | **semantically lossless**: one stanza expands to its types × uris × suites lines; keyblock `Signed-By` and un-aliasable fields warn and drop (classic cannot hold them) |

"Semantically lossless" is checked by
`semanticUnits()` in the model — the sorted set of (type, uri, suite) units
with the fields apt acts on — which is also what `apt-src-convert-dir.ts`
verifies before replacing any file. Known lossy corners, all warned:

- comments (both formats) are dropped;
- classic lines sharing a repo are not merged into one stanza, and deb822
  stanzas are not merged by option-sharing (per-line vs per-stanza option
  granularity is preserved instead of guessed);
- inline `Signed-By` keyblocks and freeform fields (`X-Repolib-Name`) have
  no classic spelling;
- `arch+`/`arch-` additive arch options (if ever encountered) stay in
  `options` and cannot cross to deb822, which has no additive form.

## Tool surfaces

All tools: stdin → stdout by default, `--file`/`--in` and `--out`
overrides, `--help` self-documentation, exit 1 on parse/IO errors with
file-and-line context, exit 2 on usage errors. Zero dependencies beyond
node; the deployed `.ts` file is the source.

- **`apt-src-classic2json.ts` / `apt-src-json2classic.ts`** — one-line
  format ↔ JSON. Emission rebuilds the legacy Compfuzor bracket style
  (`deb [ signed-by=... arch=amd64 ] uri suite comps...`).
- **`apt-src-deb8222json.ts` / `apt-src-json2deb822.ts`** — deb822 ↔ JSON.
  Canonical field order: Types, URIs, Suites, Components, Architectures,
  Enabled, Trusted, Signed-By, then `fields` verbatim.
- **`apt-src-convert-dir.ts [--to classic|deb822] [--dry-run] [--out DIR]
  [--force] [DIR]`** — detect each `*.list`/`*.sources` in DIR (default
  `/etc/apt/sources.list.d`) by extension and move it to the target format.
  The in-place `foo.list → foo.sources` replacement **is** the tool's job;
  nothing else is ever deleted. Symlinks are skipped with a warning (their
  content is owned elsewhere — e.g. Compfuzor deployments linked from
  `ETC`). `--dry-run` prints the plan; `--out` writes copies and touches
  nothing; a differing existing destination refuses without `--force`.
  Every conversion is semantic-verified through the JSON model before it
  replaces the original.
- **`apt-src-scheme.ts --to https|http [FILE...]`** — flip the scheme on
  every source URI, maintaining just the URI row per entry (below). Default
  file set: `/etc/apt/sources.list` plus `sources.list.d/*.{list,sources}`.

## Scheme tool strategy: block-in-file vs surgical

The unit of maintenance is one row: the `deb`/`deb-src` line (classic,
including commented-out ones) or the `URIs:` line (deb822, all URIs on the
line). Only the scheme substring inside the URI token changes; everything
else on the row is byte-preserved. Non-http(s) URIs (`file:`, `cdrom:`) are
never touched, and rows already on the target scheme are left alone, so the
tool is idempotent.

Ground truth established by experiment (transcripts in
[`.test-agent/apt-srctools/bif-lab/`](/test-agent/apt-srctools/bif-lab),
validated with `apt-get indextargets`):

1. **Whole-line comments are legal inside a deb822 stanza**; blank lines
   split the stanza and make apt reject the file. So marker-based row
   maintenance is *possible* in both formats — the hazard is padding, not
   comments.
2. **The deployed block-in-file 1.0.0 never pads** on insert or update —
   but its default EOF insert runs tight against the last stanza (merging
   fields into it in `.sources`), it cannot wrap an existing line, and it
   injects a `# source: <STDIN>` provenance comment per block.

Therefore the strategy is a deliberate split:

- **Adoption (first flip of a row) is surgical**: BIF cannot wrap an existing
  line, so `apt-src-scheme.ts` inserts `# apt-scheme-<n> begin/end` markers
  around the old row itself, changing structure but not content.
- **Every later change of that row goes through block-in-file** (`--name
  apt-scheme-<n> --mode ensure`), which is exactly the "maintain one
  existing row" role BIF is good at: tight in-place content replacement,
  byte-exact `--read` drift checks, idempotent no-ops.
- **Surgical fallback**: if BIF is absent, fails, or a block was hand-mangled
  into holding multiple rows, the tool rewrites the row between markers
  itself, recording why (BIF failures print a warning before the fallback).
- **Verification always**: after any write the file is re-parsed — entry
  count must be unchanged (a split stanza changes it) and every http(s) URI
  must carry the target scheme — else the original file is restored and the
  tool exits nonzero.

The residual gap (adoption, fail-closed updates, provenance noise,
stanza-awareness) is the subject of the
[BIF wishlist](/design/apt-srctools/bif-wishlist.glm53m.md); if those land,
the surgical paths shrink to nothing.

## Open questions

- **`apt-src-pin-priority.ts` is intentionally unbuilt** (the playbook's
  FUTURE comment reserves the name): rewriting pin priorities per
  distribution filter wants the same JSON-model treatment for
  `preferences.d`, which the model does not yet describe.
- **`sources.list` itself**: `apt-src-convert-dir.ts` only takes a directory
  (default `sources.list.d`). Whether the top-level `/etc/apt/sources.list`
  should be folded into directory handling (or moved by hand first, which is
  the current Debian guidance) is left to the operator.
- **Merging on conversion**: classic `deb` + `deb-src` lines for one repo
  become two deb822 stanzas (semantically identical to one `Types: deb
  deb-src` stanza). A `--merge` post-pass could canonicalize, but every merge
  is a guess about author intent; deferred until wanted.
- **Marker names are positional** (`apt-scheme-<n>`, next free id). Stable
  content-derived names (e.g. from the host) would survive row reordering by
  humans; see wishlist item 5.
- **`convert-dir` on live systems**: run it under sudo and re-run
  `apt-get update`; the tool verifies structure but cannot verify that
  removed `.list` files were not referenced elsewhere (e.g. by pinned
  preferences keyed to the old file's existence — apt keys pins on release
  properties, so this is believed safe, but has not been exhaustively
  checked).

## Cross-references

- [`doc/apt.md`](/doc/apt.md) — the authoring lane whose deb822 field
  semantics (`Components: []` for flat suites, keyblock dot-stuffing,
  `Signed-By` precedence, `APT_PREFS`) this model mirrors so authored and
  on-host sources speak the same language.
- [`design/apt-deb822/`](/design/apt-deb822/) — the wave that settled the
  authoring lane's compatibility rules (selection by presence, no source-path
  mixing, encoded inline keys); apt-srctools is the host-side complement,
  and inherits its "no pruning, deliberate ownership transitions" posture.
- [`block-in-file.src.pb`](/block-in-file.src.pb) — deploys the BIF binary
  the scheme tool prefers for row maintenance; the version skew and gaps
  recorded in the [wishlist](/design/apt-srctools/bif-wishlist.glm53m.md)
  are tickets against its upstream.
- [`script/apt-tunnel-mirrors.ts`](/script/apt-tunnel-mirrors.ts) — the
  style precedent (single-file `node --strip-types` bin, `parseArgs`,
  `node:fs/promises`, marker-delimited maintenance) and a downstream
  consumer of the same sources corpus; scheme flips change the hosts its
  discovery must see.
- [`apt-srctools.etc.pb`](/apt-srctools.etc.pb) — the deployment contract:
  bin names, the deployed-as-`.ts` decision, and the README ships with the
  tools.
