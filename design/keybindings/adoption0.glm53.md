---
type: ArchitecturalCheckpoint
title: Consumer-host topology adopted; Vicinae producer cutover landed
description: One location-typed deployment per compositor carrying user-scoped installers (niri.etc.pb, umbriel.etc.pb), conservative root adoption/migration, and the reviewed Vicinae declaration cutover — render-only, awaiting the operator's live installer run.
resource: /design/keybindings/adoption0.glm53.md
status: draft
generated: { by: model:glm53, at: 2026-10-02 }
verified: { by: unverified }
stale_after: 2026-11-02
sources:
  - resource: /design/keybindings/vicinae-proposal0.gpt61sol.md
    title: Reviewed cutover values and root-adoption policy
  - resource: /design/keybindings/implementation2.gpt61sol.md
    title: Accepted producer machinery checkpoint this adoption exercises
  - resource: /niri.etc.pb
    title: Niri consumer host with conservative adoption installer
  - resource: /umbriel.etc.pb
    title: Umbriel consumer host absorbing umbriel.user.pb
  - resource: /vicinae.src.pb
    title: Producer cutover to KEYBINDING_* declarations
  - resource: /tests/integration/keybindings_consumer_hosts.test.py
    title: Real-playbook adoption and migration proof
---

# Situation and decision

The producer/consumer machinery from
[implementation2](/design/keybindings/implementation2.gpt61sol.md) and the
[reviewed proposal](/design/keybindings/vicinae-proposal0.gpt61sol.md) left
one decision open: where the per-compositor consumer hosts live. The operator
decided **ONE deployment per compositor, `.etc`-suffixed** — a location-typed
deployment whose material renders under `/etc/opt/<compositor>` and whose
installers are **user-scoped** (the operator runs `bin/install-user.sh` as
themselves; contexts resolve `~/.config` at invocation time). "User" is an
audience of the deployment's installers, not a place for deployment material,
so there is deliberately **no `.user.pb`** anymore, and a future
"thing that runs" service-instance deployment (`.srv.pb`) is deliberately not
built now.

This slice is **render-only**: everything is generated and tested in
isolation, and no live user configuration was modified. The operator runs the
live installers after parent review (steps at the end).

# What was built

## Consumer host deployments

| Deployment | Owns |
|---|---|
| [niri.etc.pb](/niri.etc.pb) | The Niri consumer profile only: `KEYBINDING_CONSUMERS` with a user context (`~/.config/niri`), no baseline (Niri has no installed system default to layer — none is fabricated), link placement/registration. No `KEYBINDING_ACTIONS`/`KEYBINDINGS` of its own. |
| [umbriel.etc.pb](/umbriel.etc.pb) | Every role of the deleted `umbriel.user.pb`: the root include-chain template (baseline first, keybinding insertion area inside the single `include.files` array, optional personal fragments last), the staged personal fragments, the Umbriel consumer profile (`template_file` bound to the staged root; `baseline` stays the filtered default `/usr/local/share/umbriel/config.toml`), and the consumer-owned `vicinae-clipboard` patch (`umbriel: {keys: [Mod+Grave]}`, `patch: true` so it stays dormant without the producer). |

Both pin `NAME` so producers bind stable deployment roots (`/etc/opt/niri`,
`/etc/opt/umbriel`). A producer's `KEYBINDING_TARGETS` consumer entry uses the
deployment-root form, which the controller resolves to
`<root>/etc/keybinding-<target>.json` — for etc-type deployments that path
resolves through the structural `DIR/etc` exposure link to the materialized
profile at `DIR/keybinding-<target>.json`. The end-to-end test exercises this
exact form.

## Conservative adoption and migration

**Niri** (`install-user.sh` authored body, then the generated
`install-keybindings-niri.sh` host child appended by `gen_bins`):

- Missing root → minimal skeleton: just the marker pair.
- Existing root without markers → the `// compfuzor-keybindings-begin/end`
  pair is appended at EOF (trailing top-level comments are valid KDL); no
  existing line is rewritten.
- The old `vicinae` block-in-file namespace (maintained by the removed
  `install-niri.sh`) is retired once via `block-in-file --remove vicinae`:
  producers now supply those bindings inside the managed area. The
  `~/.config/niri/vicinae/` symlinks are deliberately not pruned.
- `handy`'s block ([handy.src.pb](/handy.src.pb) owns it) and all unknown
  text stay untouched.

**Umbriel** (`umbriel_seed` helper, one entry per staged file, then the host
child): missing files seed from deployment material; live files that still
**byte-match the previously managed `umbriel.user.pb` template** migrate to
the new template (the byte-match proves no user-authored text is lost); files
matching neither print a loud note and are left untouched. A custom unadopted
root then fails host assembly with the runtime's explicit area error —
operator action, never a silent rewrite. The old-template SHA-256 hashes are
pinned in `UMBRIEL_MIGRATIONS` (they equal the exact bytes the old playbook
rendered; the test embeds those bytes as historical literals and
cross-checks the hashes). A stale `keybinds-vicinae.toml` is left on disk,
merely unreferenced by the new template.

## Producer cutover ([vicinae.src.pb](/vicinae.src.pb))

- `KEYBINDING_ACTIONS`/`KEYBINDINGS` with the reviewed fixture values
  ([examples/keybindings/vicinae.yaml](/examples/keybindings/vicinae.yaml)):
  modern `vicinae://launch/<provider>/<entrypoint>` deeplink routes, Niri
  open vs Umbriel `?toggle=true` policy, `umbriel: {keys: []}` for the
  clipboard binding (the Umbriel chord comes from the consumer patch).
- `KEYBINDING_TARGETS` bound to the two consumer deployments, user
  context/scope; `KEYBINDING_PRODUCER: vicinae` (NAME is `vicinae-git`).
- Removed: the three hand-authored Niri KDL fragments, the Umbriel
  `keybinds.toml` fragment, and the `install-niri.sh`/`install-umbriel.sh`
  bodies; `ETC_DIRS` narrowed to the KDE path.
- Unchanged: every KDE resource and `install-kde.sh`, all source
  build/install/service bodies, and `install-user.sh`'s authored
  `systemctl --user enable` body (the generated target children join it as
  the scoped aggregate).

`keybinds-local.toml` lost its duplicate command-valued `Mod+Grave` entry:
the consumer-owned patch supplies that chord now (the byte-match migration
carries the edit to live files that are still managed bytes; user-edited
copies keep their entry until the user removes it).

# Verification

Passed, all render/isolation only (no live config touched):

- `ansible-playbook <niri.etc.pb|umbriel.etc.pb|vicinae.src.pb> --syntax-check`
- `python tests/integration/keybindings_consumer_hosts.test.py` — real
  playbook renders (etc-type `DIR==ETC` shape), profile shape, marker
  adoption at EOF + one-time vicinae retirement + handy/unknown-text
  preservation + idempotence + fresh-root skeleton; byte-match migration,
  no-clobber seeding, user-edit preservation with a loud note, hard failure
  on an unadopted custom root, stale fragment left unreferenced; embedded
  historical literals match the pinned migration hashes.
- `python tests/integration/keybindings_vicinae_proposal.test.py` — renders
  all three real playbooks, adopts both roots, registers the producer via
  the generated target installers through the deployment-root profile form,
  and checks every chord outcome, the toggle policy, membership groups and
  native validation, without launching applications.
- `python tests/integration/umbriel.test.py` — user-config test moved to
  `umbriel.etc.pb` (area-marked template, Mod+Grave-free local chords,
  animation values, consumer profile, native validation).
- Regression suite unchanged and green: `keybindings_generated`,
  `keybindings_dependencies`, `keybindings_empty_producer`,
  `tests/filter_plugins/keybindings_compile.test.py`.

No TypeScript changed; the concurrent JSDoc pass was untouched.

# Remaining operator steps (live)

```sh
ansible-playbook -i 'localhost,' -c local niri.etc.pb      # /etc/opt/niri
ansible-playbook -i 'localhost,' -c local umbriel.etc.pb   # /etc/opt/umbriel
ansible-playbook -i 'localhost,' -c local vicinae.src.pb   # /usr/local/src/vicinae-git

/etc/opt/niri/bin/install-user.sh       # adopt Niri root, then empty host assembly
/etc/opt/umbriel/bin/install-user.sh    # migrate/seed Umbriel config, host assembly
/usr/local/src/vicinae-git/bin/install-user.sh  # register producer into both consumers
```

Order matters: consumer adoption before producer registration. Afterwards
reload/restart the compositors to pick up the new roots (deliberately manual —
no unrequested reload is performed). Expect the Umbriel migration notes for
the three managed files; anything reporting `user edits` needs a by-hand
look. `niri validate -c ~/.config/niri/config.kdl` and
`umbriel validate -c ~/.config/umbriel/config.toml` are the post-run checks.

# Cross-references

- [Producer guide](/doc/config/keybinding-producers.md): maintained author
  entry point; the fixture cross-reference now points at the live cutover.
- [Consumer guide](/doc/config/keybinding-consumers.md): adoption/validation
  contracts these installers exercise.
- [Proposal](/design/keybindings/vicinae-proposal0.gpt61sol.md): reviewed
  values, root shapes and the seed/writer-policy choice implemented here
  (installer-level no-clobber seeding instead of a writer `once:` flag,
  because the deployment no longer renders into `~/.config` at all).
- [Noctalia desktop guide](/doc/noctalia/README.md): updated to the new
  Umbriel config owner.

# Addendum: live adoption completed (2026-10-05)

The remaining operator steps above were executed on `workhorse` on
2026-10-05, in the documented order, with exactly the expected outcomes:

- `niri.etc.pb` / `umbriel.etc.pb` / `vicinae.src.pb` rendered to
  `/etc/opt/niri`, `/etc/opt/umbriel`, `/usr/local/src/vicinae-git`.
- Niri root adopted: marker pair appended at EOF, the old `vicinae`
  block-in-file namespace retired (1 block), handy/config.d untouched.
- Umbriel: all three managed files (`config.toml`, `keybinds-local.toml`,
  `animation.toml`) byte-matched the pinned old-template hashes and migrated
  cleanly — no user-edit notes, no manual reconciliation.
- Vicinae producer registered into both consumers; memberships created.

The same session registered the second producer — `media-keys.etc.pb`
([examples fixture](/examples/keybindings/media-keys.yaml)) — and retired
the hand-written XF86Audio* block from the niri root in favor of it.
Both roots pass `niri validate` / `umbriel validate`; the running Umbriel
picked the new chain up via `umbriel msg config-reload`. This closes the
render-only state this checkpoint recorded.
