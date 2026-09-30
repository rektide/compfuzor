---
type: Design
title: apt-build local repo signing research
description: Why forky apt rejects apt-build's local file: repository despite trusted=yes, what proper signing takes, whether apt-build is worth keeping alive, and a recommendation.
status: draft
generated: { by: agent:glm53, at: 2026-09-30 }
verified: { by: none, at: null }
sources:
  - id: host-state
    resource: /etc/apt/sources.list.d/apt-build.list
    title: disabled apt-build source line and empty pool on workhorse (apt 3.3.1, forky)
  - id: apt-src
    resource: https://salsa.debian.org/apt-team/apt
    title: apt 3.3.3 source (fetched via apt-get source; behavior verified against installed 3.3.1)
  - id: apt-build-perl
    resource: /usr/bin/apt-build
    title: installed apt-build 0.12.51 Perl source (repository regeneration flow)
  - id: tracker
    resource: https://tracker.debian.org/pkg/apt-build
    title: Debian package tracker for apt-build (removal news)
---

# apt-build local repo signing — init0

## Stage setting

The apt-build source line on workhorse was disabled today (2026-09-30) after
`apt-get update` failed with `E: The repository ... is not signed.` — *seemingly*
despite `trusted=yes`. The pool at `/var/cache/apt-build/repository` has been
empty since 2025-03-15. This wave answers four questions: why current apt
rejects the line, what signing the pool properly would take, whether apt-build
is a viable backbone at all, and what compfuzor should do about it. Everything
below was verified today on this host against apt 3.3.1 (forky) using isolated
scratch copies under `~/tmp-opencode` (`Dir::State::lists` overrides, scratch
GPG home, no system state touched).

## Q1 — why forky apt rejects the line: it is not a signature regression

**The line is malformed, and it was always malformed.** The failing entry was:

```
deb [trusted=yes,arch=amd64] file:/var/cache/apt-build/repository apt-build main
```

In the one-line format, bracket options are **space-separated**; commas only
separate values *within* one option (`arch=amd64,i386`).
[sources.list(5)](https://manpages.debian.org/apt/sources.list.5.en.html) says
it plainly: *"If options should be provided they are separated by spaces … If
an option allows multiple values these are separated from each other with a
comma."*

apt's one-line parser (`pkgSourceList::Type::ParseLine`,
`apt-pkg/sourcelist.cc` in apt 3.3.x) splits the bracket content with
`ParseQuoteWord`, which only splits on whitespace. So `trusted=yes,arch=amd64`
is **one** option: key `trusted`, value `yes,arch=amd64`. Then
`debReleaseIndex::SetTrusted` → `GetTriStateOption("trusted")` →
`StringToBool("yes,arch=amd64", false)`. `StringToBool` requires a full-string
match (`apt-pkg/contrib/strutl.cc`); `yes,arch=amd64` matches nothing, so the
default `false` is returned → trusted is set to **TRI_NO** (explicitly
untrusted, not merely unset). When Release.gpg 404s,
`AllowInsecureRepositories` (`apt-pkg/acquire-item.cc`) finds no trust and no
allow-override → hard `E:`.

Empirical matrix (scratch copy of the real pool, isolated lists dir, 100%
stable across repeated runs):

| sources line | result |
| --- | --- |
| `[trusted=yes]` | **PASS** — clean `Ign` InRelease/Release.gpg, update succeeds, no warning |
| `[trusted=yes,arch=amd64]` (the failing line) | `E: … is not signed` |
| `[arch=amd64 trusted=yes]` | `E:` (same mangling, key `arch` swallows the rest) |
| `[trusted=yes arch=amd64]` (spaces) | **PASS** |
| `[trusted=yes,signed-by=-]`, `[trusted=yes,check-valid-until=no]`, any comma | `E:` |
| `[]` + `-o Acquire::AllowInsecureRepositories=true` | **PASS** as `W:` (see below) |

So: **not** an apt 3.x regression, **not** related to sqv, **not** about the
Release file contents. The same line fails identically on older apt — the
comma form was never valid. Two corroborating facts:

- apt-build's own `postinst` writes the line *without* `arch=amd64`:
  `debline="deb [trusted=yes] file:$repository_dir apt-build main"`
  (`/var/lib/dpkg/info/apt-build.postinst`), and its `config` script greps for
  exactly that form. The `arch=amd64` on this host was a hand edit — that edit
  is what broke the line.
- Reverting to the upstream form (`[trusted=yes]`) passes on this apt today,
  against the real pool, unchanged.

**Config knobs that legitimately accept an unsigned `file:` repo:**

- `[trusted=yes]` as the only/comma-free option — works (verified).
- `Acquire::AllowInsecureRepositories "true";` in `apt.conf.d` — works,
  downgrades to a warning (verified; apt.conf(5) and apt-secure(8) document
  it). Caveat: I observed one unexplained `E:`-streak with this knob while a
  root `aptitude`/packagekitd session was churning apt state on this host; it
  was not reproducible afterwards. Test before relying on it here.
- Per-repo `[allow-insecure=yes]` maps to the same code path (debmetaindex.cc
  `GetDebReleaseIndexBy`), same caveat about comma mangling — keep it
  space-separated.

One curiosity worth recording: with an **empty** pool, `apt-get update` fetches
the Release/InRelease but never queues the (0-byte) Packages index; after
dropping a real .deb in and regenerating, `Get: … Packages [339 B]` appears.
The empty pool was silently useless even when trusted.

## Q2 — what proper signing takes (verified end-to-end)

Signing works today, cleanly, against the exact apt-build layout:

1. Generate a local signing key (I used an unprotected Ed25519 key in a
   scratch `GNUPGHOME`; sqv 1.3.0 is installed and is what apt 3.3 actually
   invokes — the acquire debug shows a `sqv:` worker on InRelease).
2. Export the public key to a keyring, e.g.
   `/etc/apt/keyrings/apt-build.gpg` (mode 0644, readable by `_apt`).
3. After each repo regeneration, produce a clearsigned meta-index:
   `gpg --batch --yes -o InRelease --clearsign Release` in
   `dists/apt-build/` (or detached `Release.gpg`; InRelease is preferred).
   Mind the 0600 default of `gpg -o` — chmod 0644 afterwards.
4. Sources line: `deb [signed-by=/etc/apt/keyrings/apt-build.gpg] file:/var/cache/apt-build/repository apt-build main`.

Verified: scratch pool + real .deb → `apt-ftparchive packages` →
`apt-ftparchive release` (same command apt-build uses, with
`/usr/share/apt-build/apt-build.release.conf`) → clearsign → update fetches
InRelease + Packages with zero warnings.

**Where a hook would have to slot in — the catch.** apt-build's flow
(`/usr/bin/apt-build`): `build_repository()` (rm's `dists/apt-build/Release`,
re-runs `apt-ftparchive` — which clobbers any InRelease) and then
**immediately** `system("$conf->{apt_get} -t apt-build … install …")` in the
same invocation. There is no hook, no trigger, no config for signing anywhere
in the Perl source. Consequences per approach:

- *Post-run wrapper / `APT::Update::Post-Invoke`*: signs too late for
  apt-build's own internal install step; the install after a build would fail
  against `signed-by` (signature missing until the wrapper runs).
- *PATH shim named `apt-ftparchive`*: apt-build calls it via `system()`
  without an absolute path, twice per regeneration; a shim could run the real
  binary and, on `release DIR`, also emit `DIR/InRelease` as a side effect.
  Workable but gross; it must know the key and keep parity with the two
  call sites (top-level + dists).
- *dpkg-divert wrapper around `/usr/bin/apt-build`*: same too-late problem as
  the post-run hook.
- *`trusted=yes` (correctly formatted)*: sidesteps all of this — apt-build's
  internal install then works unsigned, matching upstream's own design.

## Q3 — is apt-build viable at all? No: it is dead upstream

- Removed from unstable **2025-09-30** (RoQA: *"orphaned, abandoned"*,
  closing bug [#1116281](https://bugs.debian.org/1116281)); removed from
  testing 2025-09-16; maintainer is the QA Group.
  [tracker](https://tracker.debian.org/pkg/apt-build),
  [removals log](https://ftp-master.debian.org/removals-full.txt).
  `apt-get source apt-build` fails on this host because the package no longer
  exists in any configured suite; only bookworm/stable carries 0.12.51.
  This host runs a bookworm binary against forky apt — an unsupported
  combination that will not receive fixes.
- The last upstream activity is the 0.12.51 upload (Dec 2024); the salsa repo
  is dormant. No signing support exists or is planned; no BTS patch adds it.
- **reprepro** is alive again (maintained: 5.4.6 in stable/testing/unstable,
  5.5.1 in experimental) and is the right tool for a managed signed local
  pool (incoming queue, GPG signing, `remove`/`list`). But it cannot slot
  under apt-build: apt-build deletes and regenerates the flat pool itself.
  reprepro only makes sense as the backbone of a *replacement* flow.
- Replacement flows compfuzor already has pieces for: `apt-get source` +
  `debuild` + `apt-ftparchive` (all that apt-build automates, minus the
  compiler-wrapper `Olevel/mtune/make` optimization gimmick via
  `/usr/lib/apt-build/apt-build-wrapper`), or `sbuild-chroot.pb` for real
  chrooted builds. `doc/apt.md` already provides the signed-by keyring lane
  for any such local repo, and explicitly advises against `Trusted: yes` as a
  missing-key workaround.

## Q4 — recommendation

**Keep the repo disabled; do not invest in signing.** Sized to reality: the
pool has been empty for 1.5 years, the tool is dead upstream and running an
unsupported bookworm binary, and nothing on this host consumes it. Options, honestly ranked:

1. **Leave disabled (recommended).** Zero maintenance, honest state. If a
   one-off optimized build is ever wanted, `apt-get source` + `debuild` +
   `apt-get install ./the.deb` needs no repo at all. To fully retire: purge
   `apt-build` (its postinst removes the source line) and reclaim
   `/var/cache/apt-build`.
2. **If apt-build must run again** (cheap fix, no signing): restore the
   upstream line verbatim — `deb [trusted=yes] file:/var/cache/apt-build/repository apt-build main` — no `arch=`, no commas. Verified working on
   apt 3.3.1. This contradicts `doc/apt.md`'s "don't use Trusted: yes" stance
   only in the narrow sense that this is a root-owned, single-user, `file:`
   pool; the risk is local tampering only.
3. **If a standing signed local repo is ever wanted**: build it as its own
   compfuzor subsystem around reprepro (or `apt-ftparchive` + gpg in a bin),
   with a vendored keyring via the `APT_TRUSTED`/`Signed-By` lane in
   `doc/apt.md` — and drop apt-build from the flow rather than trying to hook
   it. The hook-in constraint in Q2 makes "sign after apt-build" strictly
   worse than "don't use apt-build".

A compfuzor implementation sketch for option 3 (only if ever needed): an
`apt-local-repo` type (`etc.pb`) owning the sources entry + keyring + a
`sign-repo` bin (`apt-ftparchive` → `gpg --clearsign` → 0644), so no state is
generated by a dead third-party tool. Nothing here needs building today.

## Cross-references

- [`design/apt-srctools/apt-srctools.glm53m.md`](/design/apt-srctools/apt-srctools.glm53m.md) —
  documents the same `trusted=yes,arch=amd64` blob as *"a single `trusted`
  option whose trailing junk apt ignores"*. That understates it: the junk
  makes `StringToBool` return its default, so trusted resolves to **TRI_NO**
  (actively untrusted), not "ignored". The blob's own roundtrip-preservation
  is unaffected. The `bif-lab/` ground-truth probes there used
  `apt-get indextargets` with a `Dir::State::lists` override, which this
  session found does not honor the override for target enumeration.
- [`doc/apt.md`](/doc/apt.md) — compfuzor's signed-by keyring lane and the
  `Trusted: yes` guidance this recommendation leans on.
- [`sbuild-chroot.pb`](/sbuild-chroot.pb) — the existing chrooted build
  subsystem that supersedes apt-build for any serious rebuild workflow.

## References

- apt one-line option parsing: `apt-pkg/sourcelist.cc` `ParseLine` (bracket
  tokenization, `]`-strip hack), apt 3.3.3 source (`apt-get source apt`).
- Trust decision: `apt-pkg/acquire-item.cc` `AllowInsecureRepositories`,
  `TargetIsAllowedToBe`; `apt-pkg/deb/debmetaindex.cc`
  `GetDebReleaseIndexBy`, `SetTrusted`, `GetTriStateOption`;
  `apt-pkg/contrib/strutl.cc` `StringToBool` (full-string match, default
  fallback).
- [sources.list(5)](https://manpages.debian.org/apt/sources.list.5.en.html) —
  "options … separated by spaces; multiple values … separated … with a comma".
- Installed apt-build: `/usr/bin/apt-build` (`build_repository` ~line 345,
  `make_release_file` ~368, internal install ~599),
  `/usr/share/apt-build/apt-build.release.conf`,
  `/var/lib/dpkg/info/apt-build.postinst` (the line it writes).
- Removal: [tracker.debian.org/pkg/apt-build](https://tracker.debian.org/pkg/apt-build);
  `removals-full.txt` entry `[Date: Tue, 30 Sep 2025] [ftpmaster: Thorsten
  Alteholz] … apt-build | 0.12.51 … RoQA; orphaned, abandoned`, bug
  [#1116281](https://bugs.debian.org/1116281).
- reprepro availability: `rmadison reprepro` (5.4.6 in unstable, 5.5.1 in
  experimental).
- Scratch evidence: `~/tmp-opencode/apt-build-research/` (repo copy, option
  matrix transcripts, scratch GPG home, signed-pool fixture).
