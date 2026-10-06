# Mise cache inventory and manual cleanup

Both [`mise.opt.pb`](/mise.opt.pb) and [`mise2.opt.pb`](/mise2.opt.pb) install
`bin/mise-cache.ts` and `bin/config-mise-cache.ts`. Run the TypeScript entry
points directly with Node:

```sh
node /opt/mise-main/bin/config-mise-cache.ts
node /opt/mise-main/bin/mise-cache.ts status --fast
node /opt/mise-main/bin/mise-cache.ts status
node /opt/mise-main/bin/mise-cache.ts list
node /opt/mise-main/bin/mise-cache.ts gc pnpm uv --dry-run
node /opt/mise-main/bin/mise-cache.ts clear cargo --dry-run
```

Replace the deployment path with your `DIR`. The aggregate `status.sh` uses
`status --fast`: it resolves paths but does not run `du`. Full measurement can
be expensive. Catalog paths are resolved by native read-only queries where
available, otherwise authored environment-aware defaults.

## Topics and actionable leaves

The catalog keeps existing leaf selection keys. Optional `group` and `kind`
labels add reporting, not a new command framework or group-wide deletion API.
Node groups npm/pnpm/yarn/Prettier, Go groups modules/builds, Python groups
pip/uv, and JVM groups Gradle/Maven. Bun, Deno, .NET and Mise remain distinct.

Rust reports a topic total and these subtotals:

| Kind | Leaves | Meaning |
|---|---|---|
| Toolchains | `rustup`, `rust-mise` | Installed rustup toolchains and mise-managed Rust versions; visibility only |
| Libraries | `cargo` | Cargo registry and Git sources/caches; each root gets its own amount |
| Ancillary | `rustup-cache` | rustup downloads, temporary staging, update hashes and settings; visibility only |

`rustup` now measures `RUSTUP_HOME/toolchains`, not all of `RUSTUP_HOME`.
`cargo` still selects registry and Git together for manual clearing. Neither
installed toolchains nor local state is advertised as cache GC. `gc --all`
does **not** run `mise prune --tools`; installed-tool pruning is a separate
deliberate operation. Status queries `mise ls --prunable --json` and reports
an unavailable query rather than claiming there are no candidates.

## Accounting and limitations

- Sizes are `du -sk` allocated storage, displayed in IEC units, **not guaranteed
  reclaimable bytes**. Libraries and installed tools are intentionally distinct.
- Every rollup canonicalizes existing roots, deduplicates aliases/symlinks, and
  removes descendants already covered by a parent. The grand `TOTAL` measures
  the union of physical roots, not a sum of displayed leaf or topic totals.
- `mise-installs` covers all mise-managed tools, including `rust-mise`.
  Consequently Mise and Rust topic totals can overlap; they are not additive.
  Expanded child rows are informational and need not sum exactly to their root
  (directory metadata, links and shared files). Identical measurement requests
  are reused within one invocation; different unions still require `du` passes.
- Failed `du` measurements print `unknown`, never a fabricated zero. This is
  an inventory snapshot, not a transaction; concurrent filesystem changes can
  affect the result. Rust ancillary reporting enumerates known roots rather
  than scanning arbitrary `~/.cache` or claiming complete ownership of rustup.
- Mise paths honor `MISE_CACHE_DIR`, `MISE_DATA_DIR`, `MISE_INSTALLS_DIR`,
  `MISE_STATE_DIR` and the relevant XDG defaults. Explicit state/install
  overrides are complete roots. Cargo/rustup and other leaves use their own
  authored overrides; native query output is accepted only on success as an
  absolute path. NuGet clearing targets measured global packages, not all locals.

## Discovery and safety

`config-mise-cache.ts` stages `etc/mise-cache.areas.json` atomically from
`mise ls --json --installed`: base areas plus mapped installed tools. Failed
or malformed discovery exits nonzero and leaves any previous catalog intact.
Until a catalog is staged, the inventory uses the rendered union of known
areas. Successful empty discovery legitimately stages only base areas.

Mise2 uses its deployment's isolated config root for mise queries/actions;
data/cache storage remains shared unless separately redirected. Run catalog
generation again after installing or removing tools, or after rendering updated
area definitions.

Cleanup is explicitly selected with leaf names or `--all`. `--dry-run` prints
actions without executing them; read-only path queries still run. Executable
availability is checked through filesystem/PATH lookup, never by launching a
bare tool. Native clear commands are preferred where authored; unavailable
commands fall back to removal of declared roots. No background reconciliation,
automatic cleanup, or undeclared-root scan is performed.

## References and verification

- [`files/mise-cache.ts`](/files/mise-cache.ts) — runtime inventory and leaf actions.
- [`files/config-mise-cache.ts`](/files/config-mise-cache.ts) — staged discovery.
- [Rust storage playbooks](/doc/rust-storage/README.md) — separate mise-compatible
  sccache and scheduled Cargo build-artifact sweeps. These are not the registry,
  Git-cache, or toolchain cleanup actions inventoried here.
- [Bin compositors](/doc/bins.md) — explicit config-lane action and aggregate status integration.
- [`tests/integration/mise_cache.test.py`](/tests/integration/mise_cache.test.py)
  — isolated render of both playbooks, stubbed allocation/query/action checks,
  Rust alias/nested-root accounting, override paths and failed-discovery preservation.
- [`jdx/mise` prunable JSON implementation](https://github.com/jdx/mise/blob/main/src/cli/ls.rs)
  and [environment roots](https://github.com/jdx/mise/blob/main/src/env.rs) —
  verified upstream command/data shape and path precedence.

```sh
python3 tests/integration/mise_cache.test.py
```
