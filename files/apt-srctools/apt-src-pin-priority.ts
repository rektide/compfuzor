#!/usr/bin/env -S node --strip-types
/**
 * apt-src-pin-priority.ts -- NOT IMPLEMENTED. This file is the living
 * specification for a future tool. It aspires to rewrite apt pin
 * priorities for repos matching a distribution filter, and it is being
 * written LAST, with the full benefit of the settled solutions in its
 * sibling tools (apt-src-model.ts, apt-src-scheme.ts).
 *
 * ===========================================================================
 * WHAT IT ASPIRES TO BE
 * ===========================================================================
 *
 * Rewrite the `Pin-Priority` value of pin stanzas whose pin targets a
 * matching distribution -- e.g. "forky gets 600, sid gets 200,
 * experimental gets 100" -- so a mixed-suite host can retune its pin
 * policy in one command instead of editing N preferences files.
 *
 * Narrow start (hardcoded here, generalize later):
 *
 *   const PRIORITIES = { forky: 600, sid: 200, experimental: 100 };
 *
 *   sudo apt-src-pin-priority.ts            # apply the hardcoded map
 *
 * Generalized CLI it grows into:
 *
 *   apt-src-pin-priority.ts --set forky=600 --set sid=200
 *   apt-src-pin-priority.ts --filter suite=forky --priority 600
 *   apt-src-pin-priority.ts --filter origin=Debian --priority 700   # later
 *   apt-src-pin-priority.ts --dry-run [--check]
 *
 * ===========================================================================
 * INPUTS IT MUST HANDLE (both apt_preferences(5) syntaxes)
 * ===========================================================================
 *
 * - deb822 stanza pins in /etc/apt/preferences.d/*.pref and *.pin:
 *     Package: *
 *     Pin: release n=forky
 *     Pin-Priority: 600
 * - legacy one-line pins (files/_apt-pin era, three-line form above and the
 *   one-line `* release n=forky 600` form).
 * - A stanza matches a distribution when its `Pin:` expression references
 *   it: `release n=<dist>` today; `release a=<archive>` and origin/label
 *   filters later. Parsing may lean on apt-src-model.ts conventions
 *   (comment lines legal mid-stanza, blank lines separate stanzas) but
 *   preferences stanzas are NOT source stanzas: the model gains its own
 *   pin parser rather than overloading parseDeb822.
 *
 * ===========================================================================
 * ROW MAINTENANCE CONTRACT (inherit from apt-src-scheme.ts)
 * ===========================================================================
 *
 * - Maintain ONLY the `Pin-Priority:` row (or the trailing priority token
 *   of a one-line pin) -- never rewrite the whole stanza.
 * - Prefer block-in-file managed blocks: whole-line comment markers
 *   (`# apt-pin-<id> begin/end`) are legal inside preference stanzas.
 *   Adoption of an existing row is still surgical today; see
 *   design/apt-srctools/bif-wishlist.glm53m.md items 1 (adoption) and 2
 *   (fail-closed update) -- landing those in BIF removes the surgical path
 *   here too.
 * - After every write: re-parse, assert stanza count unchanged and every
 *   matching stanza now carries its new priority; restore the original
 *   text on any failure.
 * - Skip symlinks with a warning (managed elsewhere), --follow resolves to
 *   the referent FIRST so block-in-file's atomic rename cannot split-brain
 *   a link (see apt-src-scheme.ts for the postmortem).
 * - Never add or remove stanzas; a distribution in the map with no
 *   matching stanza reports "no match", it does not fabricate a pin.
 *
 * Exit codes: 0 applied/no-op; 1 any file failed; 2 usage error.
 */

console.error(`apt-src-pin-priority.ts: not implemented -- this file is the spec.
See the comment block at the top of this script (and
design/apt-srctools/) for what it aspires to be. Retune pins by hand for
now, or extend this tool along the contract it documents.`);
process.exitCode = 2;
