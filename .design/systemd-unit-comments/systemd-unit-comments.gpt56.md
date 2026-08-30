---
type: Design
title: "systemd-unit-comments: per-section comments in generated units"
description: A `comments` key in any SYSTEMD_<SECTION>S dict renders `# ...` lines directly above the [Section] header in files/systemd.unit — across top-level vars, SYSTEMD_ROOTS per-root sections, and SYSTEMD_DROPIN(S) drop-ins.
resource: /home/rektide/src/compfuzor/.design/systemd-unit-comments/systemd-unit-comments.gpt56.md
tags: [compfuzor, systemd, template, comments]
status: stable
generated: { by: llm:gpt56, at: 2026-08-30T00:00:00Z }
sources:
  - id: systemd-unit-template
    resource: /files/systemd.unit
    title: files/systemd.unit — the section() macro renderer
  - id: vars-systemd-unit-tasks
    resource: /tasks/compfuzor/vars_systemd_unit.tasks
    title: vars_systemd_unit.tasks — _merged_sections combine chain and the three render paths
  - id: systemd-yaml
    resource: /vars/systemd.yaml
    title: vars/systemd.yaml — SYSTEMD_TYPE_CONFIG section lists and per-section defaults
  - id: comments-test
    resource: /tests/integration/systemd_unit_comments.test.py
    title: tests/integration/systemd_unit_comments.test.py — the three-layer test
  - id: plan-systemd-refactor
    resource: /PLAN-systemd-refactor.md
    title: PLAN-systemd-refactor.md — the free-form-sections unit generation refactor this rides on
---

> Model note: written under OpenCode by a GPT-5.6 family model via the
> OpenAI provider; the exact reasoning tier could not be confirmed from
> inside the session, so the generic `gpt56` suffix is used.

# `comments:` — attach prose to generated unit sections

compfuzor playbooks generate systemd units from per-section dict vars:
`SYSTEMD_UNITS` ([Unit]), `SYSTEMD_SERVICES` ([Service]),
`SYSTEMD_SOCKETS` ([Socket]), `SYSTEMD_INSTALLS` ([Install]), and every
other section listed per unit type in `SYSTEMD_TYPE_CONFIG`
([vars/systemd.yaml](/vars/systemd.yaml)). Playbook authors wanted a way
to attach explanatory prose to a section that renders as `# ...` comment
lines immediately **above** the `[Section]` header — where it documents
the section as a whole rather than a single directive.

## Usage

Add a `comments` key inside any section dict. The value is a string
(usually a YAML block scalar) or a list of strings:

```yaml
SYSTEMD_SERVICES:
  comments: |
    Type=notify pairs with the daemon's sd_notify READY;
    the socket unit owns the bind, so we never unlink.
  Type: notify
  ExecStart: /usr/bin/foo
```

renders

```systemd
# Type=notify pairs with the daemon's sd_notify READY;
# the socket unit owns the bind, so we never unlink.
[Service]
Type=notify
ExecStart=/usr/bin/foo
```

Every rendering path supports it identically, because they all render
through the same [files/systemd.unit](/files/systemd.unit) template:

- **Top-level section vars** (`SYSTEMD_SERVICES` etc. in the playbook).
- **`SYSTEMD_ROOTS` per-root sections** — e.g.
  `watchwomanSocket.SYSTEMD_SOCKETS.comments`. Per-root comments override
  global ones (they are merged like any other field, see below).
- **`SYSTEMD_DROPIN` / `SYSTEMD_DROPINS` specs** — the drop-in path
  builds `UNIT_VARS` straight from the spec's section dicts, so comments
  work there for free:

```yaml
SYSTEMD_DROPINS:
  - name: hardening
    target: demo.service
    SYSTEMD_SERVICES:
      comments: defense in depth: lock the unit down further
      NoNewPrivileges: true
```

renders `demo.service.d/hardening.conf` as:

```systemd
# defense in depth: lock the unit down further
[Service]
NoNewPrivileges=True
```

List values render each entry as its own line (entries may themselves be
multiline):

```yaml
SYSTEMD_SOCKETS:
  comments:
    - "%t == $XDG_RUNTIME_DIR"
    - the socket unit owns the bind
  ListenStream: "%t/demo.sock"
```

## Rendering rules

- Each line is prefixed with `# ` (with the space). Empty lines become
  a bare `#`, so paragraph breaks inside a block survive:
  `first\n\nsecond` renders `# first` / `#` / `# second`.
- Trailing whitespace is stripped per line. Leading whitespace is
  preserved (write prose without a leading `#` — lines are prefixed
  verbatim, so an authored `# foo` renders as `# # foo`).
- Blank lines at the very start/end of the comment block are dropped:
  a YAML `|` block scalar's clipped trailing newline is syntax, not
  content, and must not become a stray bare `#` above every header.
- Empty string, empty list, `false`, `None`, and whitespace-only values
  render nothing.

## Design decisions

**Comments-only sections still emit the header.** The template
previously emitted `[Name]` only when a section dict had items. Now the
gate is "has non-`comments` fields **or** comment lines". A section
whose only content is `comments` renders the comments followed by the
bare `[Section]` header. The alternative (comments without a header)
was rejected: free-floating comments between sections would visually
attach to the *wrong* section, while comments above an empty header are
unambiguous and systemd-valid. This keeps the comment anchored to its
section at the cost of a directive-less header in a rare edge case.

**Why `comments` cannot collide with a real directive.** systemd
directive names are CamelCase (`ExecStart`, `WantedBy`, ...); no section
systemd defines — [Unit], [Service], [Socket], [Install], [Mount],
[Timer], [Path], [Network], and the netdev family — has a directive
named `comments`. The lowercase key is therefore reserved by convention
inside section dicts, and the field loop explicitly skips it (asserted
by a `no comments= directive ever emitted` test). If systemd ever grows
a lowercase `comments=` directive, that branch is the place to look.

**Merge semantics: most specific scope wins, comments are not
concatenated.** `comments` is a plain scalar (string) or list to
ansible's `combine(recursive=True)`, so it flows through the
`_merged_sections` chain in
[tasks/compfuzor/vars_systemd_unit.tasks](/tasks/compfuzor/vars_systemd_unit.tasks)
unchanged — `defaults | combine(global | combine(root, recursive=True),
recursive=True)` at the two section loops, and a direct pass-through on
the drop-in path. Consequences, verified with ansible's real `combine`
filter: a root comment *replaces* a global comment (same semantics as
`Type` or any other field — layering prose across scopes would be
surprising), and defaults could in principle ship a `comments`
(none do today).

**Error behavior is unchanged.** Falsy section data (`false`, `None`,
missing) still renders nothing; truthy non-mapping data (a bare string
where a dict belongs) still fails loudly via `.items()`.

## Implementation

All logic lives in the `section(name, data)` macro at the top of
[files/systemd.unit](/files/systemd.unit):

1. pull `data.get('comments')`, split strings on `\n` (list entries
   too), trim blank lines from both ends of the block,
2. gate the section on `comment_lines or field_keys` where
   `field_keys = data.keys() | reject('eq', 'comments')`,
3. render each comment line, then `[Name]`, then the directive loop
   which skips the `comments` key.

No task-file changes were needed — the merge chain passes the key
through untouched (read the code, then proved it both with
`ansible.plugins.filter.core.combine` and end-to-end).

## Testing

[tests/integration/systemd_unit_comments.test.py](/tests/integration/systemd_unit_comments.test.py)
(a standalone executable script, no pytest — matching
`tests/integration/*.test.py` conventions) covers three layers:

1. **Hermetic jinja2 renders** of the template with a stubbed
   `lookup('vars', ...)` — exact-output checks for strings, lists,
   multiline entries, rstrip, interior bare-`#`, end-blank trimming,
   falsy values, comments-only sections, the no-leak guarantee, all
   section kinds, the global-vars lookup fallback, and the
   loud-failure case. (Plain jinja2 matched ansible's engine on every
   case checked, including full e2e renders; the template only needs
   `lookup` stubbed for the hermetic layer.)
2. **The merge chain** via ansible's real `combine` filter, replicating
   `_merged_sections` and asserting most-specific-scope-wins for
   `comments`.
3. **End-to-end `ansible-playbook`** runs importing
   `tasks/compfuzor/vars_systemd_unit.tasks` with top-level vars,
   `SYSTEMD_ROOTS` (including the global-`SYSTEMD_UNITS`-merges-into-
   roots interaction and `SYSTEMD_SERVICES_DEFAULT` defaults), and
   `SYSTEMD_DROPINS`, comparing full rendered units. The probe playbook
   is written dot-prefixed to the repo root (gitignored as
   `.test-agent*`) because `lookup('template', 'files/systemd.unit')`
   resolves relative to the playbook directory.

Run it with:

```sh
python3 tests/integration/systemd_unit_comments.test.py
```

## Cross-references

- [PLAN-systemd-refactor.md](/PLAN-systemd-refactor.md) — the refactor
  that made units free-form section dicts; `comments` is a small
  follow-on capability in the same shape.
- [tasks/compfuzor/vars_systemd_unit.tasks](/tasks/compfuzor/vars_systemd_unit.tasks)
  — the three render paths (top-level, roots, drop-ins) and the combine
  chain the key must survive.
- [vars/systemd.yaml](/vars/systemd.yaml) — `SYSTEMD_TYPE_CONFIG`
  (which section vars exist per unit type) and the per-section
  `*_DEFAULT` dicts that merge beneath authored values.
- [atuin.src.pb](/atuin.src.pb) — a `SYSTEMD_ROOTS` socket+service
  example; its inline YAML comments are exactly the kind of prose that
  can now move into the generated units as `comments:`.
- `.design/merge-star/` — the merge-pipeline design wave; documents the
  `combine`-family semantics this feature relies on (scalar values
  replace, never concatenate).
