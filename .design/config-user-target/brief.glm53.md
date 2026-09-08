# config-user-target design brief — deltas + constellation

Shared coordination brief for the `.design/config-user-target/` rounds.
Base: `draft0.solx.md` (status-only proposal). `draft1.solx.md` (strategies,
install-driving, ETC_FILES targets) was in flight when these deltas arrived
and predates them. Authored by the parent session (glm53) from the human's
direct decisions; everything under "Deltas" is binding direction unless the
human says otherwise.

## Deltas since draft0/draft1 prompts

### D1 — cmp decides, diff3 explains (draft1 stands; CORRECTED)

**Correction (supersedes the earlier phrasing of this section):** the human
confirmed they are fine with drift decided by `cmp` — draft1's design is
correct as written ("All byte drift is decided with cmp; diff/diff3 are
explanatory only", draft1 ~189 and ~588). The requirement is only that
**diff3 remains the human-facing output**: machines get `cmp` booleans,
humans get the three-way report. The earlier draft of this section
("no cmp dual-path, parse `^====` headers") was a misreading of the human
and is retracted; no section-header parsing contract is needed.

Consequences, per draft1 unchanged:
- `--threeway` bitset from pairwise cmp: bit 1 = candidate≠materialized;
  bit 2 = materialized≠user snapshot; 3 = both. Operational failures →
  exit 4.
- `--check`/reporters stay 0/1/2 (drift bits internal).
- diff3 output printed for humans in three-way reports; unified diff for
  two-way artifact reports; symlink topology predicates stay type tests.

### D2 — `link` strategy gains the drop-in target shape

Target grammar: `file:` (exact path, e.g. the zimfw.conf evidence link) or
`dir:` (drop-in directory; link name = output basename). Live exemplar:
`jujutsu.src.pb` symlinks each `etc/*.toml` into `~/.config/jj/conf.d/`
(jj merges `conf.d/*.toml` itself). This is the inverse of zim's `zimrc.d`
remote pattern: there contributors symlink fragments INTO a dir the assembler
consumes; here we symlink materialized pieces OUT into a dir the consumer
merges. Preconditions: the consumer must support a drop/merge dir. Status per
expected link: exists, right target, resolves. Orphan extra files in the
consumer dir are out of scope (no-prune philosophy).

### D3 — polarity flip: assemble-into-user (the human's primary direction)

Human's words: "i want to try to push/lift config to the user actually. the
repo can have it's canonical but i'd rather assemble the user's for the user
so the user can customize and still have tools."

Model: canonical fragments stay repo/ETC-owned; the assembled OUTPUT can be
the user's own file. Managed blocks are updated in place; unmanaged content
in the user's file is the user's customization — preserved and NOT drift.
Drift = managed-block bytes ≠ candidate block bytes. `block-in-file`'s
`--additive` mode offers a second customization tier (added lines inside a
managed block persist). Canonical ETC materialization becomes optional
evidence, not a required intermediate. Existing seam proving this is not
new machinery: `clickpad.user.pb` already emits a CONFIGS assembly
(`processor: concat`) to a user-space dir (`dir: "{{home.stdout}}"`) under
USERMODE. Draft2 must reconcile deploy-down (draft0/draft1 model) with
assemble-into-user — likely one target grammar, two poles (output-in-ETC +
replicate vs output-is-user-file + update-in-place).

### D4 — scope + dir-class target properties

Human's words: "we need targets that are system and user. ideally we can
specify the target as a dir like 'var' or 'log' or 'etc' and it can do the
right thing in many cases? maybe we make a property for that. then another
property for other more clearly specified forms."

Target grammar gains: `scope: system|user` plus a named dir class —
`etc`/`config`, `var`/`state`, `log`, `cache`, `bin`, `share` — resolved
per scope through the FHS↔XDG duality the repo already encodes
(`ETCS_DIR` /etc/opt ↔ `USERMODE_ETCS_DIR` ~/.config at
`vars/common.yaml:52`; /var ↔ ~/.local/state; /usr/local/bin ↔
~/.local/bin). CRITICAL principle from
[`.design/global-usermode/init0.opencode.md`](../global-usermode/init0.opencode.md):
per-user paths resolve at RUNTIME for the invoking user ($HOME/%h style),
never baked at deploy time — "it is better to do nothing than go hard on
that". The second, explicit property carries precise forms: exact `file:`
paths, or the structured `{env, default, suffix}` override shape for
ZDOTDIR/BASH_RC-style cases. Example where the dir class "does the right
thing" in both scopes: systemd drop-ins — `dir: config` +
`systemd/system/<unit>.d/` resolves to /etc/systemd/system/... or
~/.config/systemd/user/...

## Constellation not yet fed to the design rounds

- [`.design/global-usermode/init0.opencode.md`](../global-usermode/init0.opencode.md)
  — system-deploy/user-activate precedent; `SYSTEMD_INSTALL: user` verified,
  `separate` empirically broken; runtime-resolution principle D4 relies on.
- [`.design/gen-user/`](../gen-user/) — user generation work (`init.md`,
  `init.0.gpt56t.md`).
- `xdg-dirs.user.pb` / `xdg-dirs.pb` — XDG dir materialization; the existing
  XDG surface the dir-class vocabulary should agree with.
- `clickpad.user.pb` — CONFIGS output already in user space (D3 seam).
- `jujutsu.src.pb` — conf.d drop-in links (D2 exemplar).
- block-in-file repo (`~/src/block-in-file`) capability surface beyond
  `--read` that strategy semantics should be designed against: `--additive`
  (+`--additive-before/after`), `--envsubst` (+exclude), `-C create`,
  `--anchor`, tag merging, `--remove-match`. README "Full Usage" is the map.
- Live-deployment lessons: generated bins default `$DIR` from the ambient
  environment (an exported foreign `DIR` made `status.sh` source the wrong
  `env.export` and die on `set -u` — user-path resolution must be explicit
  about which environment it trusts); zim's authored `status.sh` masks the
  generic STATUSES orchestrator; interrupted config runs have leaked
  `.config-candidate.*` temps in /etc/opt (transaction hygiene).

## Carried open questions

- Zim's first declared target: unanswered by the human — carry both options
  (zimfw.conf symlink, zero-behavior-change; vs copy-mode adoption with the
  install-step trade-off) with a recommendation.
- Install ordering/failure semantics in config.sh apply mode.
- ETC_FILES target seam timing (mise migration) vs CONFIGS-first.
- Orphan/extra-file policy in drop-in dirs (default: out of scope).
