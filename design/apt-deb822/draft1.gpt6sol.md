---
type: Design revision
title: apt deb822 delivery and compatibility corrections
description: Implementation checkpoint correcting draft0's pin precedence, keyblock encoding and repo-only install-time ordering.
status: draft
generated: { by: agent:gpt6sol, at: 2026-09-24 }
verified: { by: none, at: null }
sources:
  - id: draft0
    resource: /design/apt-deb822/draft0.glm53m.md
    title: apt deb822 initial design
  - id: apt-manual
    resource: https://manpages.debian.org/apt/sources.list.5.en.html
    title: sources.list(5), deb822 and embedded Signed-By
---

# apt deb822: implementation checkpoint

The existing [draft0](/design/apt-deb822/draft0.glm53m.md) maps the two apt
lanes well. This revision preserves its `APT:`/`APTS:` stanza surface and
render-time-first, install-time-second commits, with these corrections:

1. **Selection by presence, not truthiness.** `APT: {}` must fail validation,
   never silently fall back to legacy `APT_REPO`. Only `APT` or `APTS` selects
   the new source path; the existing scalar `APT_PIN` is never a selector.
   New freeform pin declarations use `APT_PREFS` (mapping or list). Pin-only
   legacy playbooks must not be repurposed accidentally.
2. **No mixing source paths.** The new path never emits a legacy `.list` or
   downloads `APT_LIST_URL`, even if both are supplied. The old `APT_PIN`
   scalar and `APT_PIN_PRIORITY` are ignored when `APT`/`APTS` is selected.
   Explicit `APT_PREFS` may accompany the new source path; it does not
   itself select the source path.
3. **Inline keys are encoded.** `Signed-By` inline PGP keyblocks are not
   emitted verbatim: each line needs a leading space; empty lines become
   ` .` (Deb822 dot-stuffing). The renderer must reject arbitrary multiline
   fields rather than silently writing invalid or injectable stanzas.
4. **Trust is never inferred.** No `Trusted: yes` default; `APT_TRUST: false`
   remains inert. Explicit `Trusted` is an apt security override, not a
   synonym for skipping `Signed-By`. Missing acquired keyrings do not produce
   dangling `Signed-By`; a source without one uses apt's system trust.
5. **Repo-only install-time delivery.** Source installation is independent of
   `PKGS` and of `APTLANE_BYPASS`. It must run *before* `install-apt.sh` in
   the packages phase and not require the package manager binary until the
   optional index refresh. The render-time source installer must not be
   suppressed by `PKGS_BYPASS`. The install-time script is not gated by
   `APT_BYPASS` (the render-time bypass).
6. **Stay away from legacy internals.** The `.list` template and legacy
   per-repo update are left intact. New templates and tasks operate on
   explicit `.sources` and `.pref` paths, and skip update if no new source
   was declared. No automatic cleanup of previously emitted files.
7. **Installation is not the same as generation.** The generated files live
   under `DIR/etc` and are readable to the `_apt` account through their
   parents. Render-time delivery publishes them to `/etc/apt` and optional
   keyrings to `/usr/share/keyrings`. A separate install-time leaf performs
   the same publication followed by an optional update, so a generated
   deployment can bootstrap packages without re-running Ansible. Neither
   delivery prunes undeclared/old `.list` files: warn when migrating and
   remove old files deliberately.

Convergence tests should use temporary target directories and no sudo, mock
the update command, and confirm new-over-legacy precedence, output order,
source-only playbooks and unchanged legacy rendering. The main apt surface
must not depend on the package `gen_apt.tasks` running.

## Cross-references

- [`draft0.glm53m.md`](/design/apt-deb822/draft0.glm53m.md) — initial assessment and proposed defaults.
- [`doc/subsys.md`](/doc/subsys.md) — packages-lane ordering and bypass semantics.
- [`skill/systemd.md`](/skill/systemd.md) — mapping-over-defaults authoring precedent.
