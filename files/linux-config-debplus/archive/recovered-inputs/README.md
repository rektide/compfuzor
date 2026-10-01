# Recovered inputs from the interrupted `/usr/local/src/linux` working copy

Recovered 2026-10-01 from the jj working-copy history of `/usr/local/src/linux`
(colocated git/jj; read via read-only `git cat-file` on the git objects). An
interrupted 2026-09-15 `jj new master@origin` materialization deleted these
uncommitted root files from the tree; they survive in the hidden prior
working-copy commit `df0fa920ad9ab6cc8f11bc65a0addb21cd46be84` (change
`xvuklsmr`, hidden, protected by `refs/jj/keep/df0fa920…`). No other copy of
the two `.xz` configs exists on disk (checked `/usr/local/src`, `/boot`).

These are Debian **packaging inputs** for the debplus config lineage — relevant
baseline material for config-diff research. The `debian/` analysis directory of
this bundle is owned separately; this directory only preserves the raw inputs.

## Contents and provenance

| file | original path (tree root) | source commit | git blob | bytes | sha256 |
|---|---|---|---|---|---|
| `config-6.13-amd64.xz` | `config-6.13-amd64` | `df0fa920ad9a…` (`xvuklsmr/1`) | `c105c66843b2…` | 282,839 | `83173838c8958d2166856f910463dfece727026cbd4712d57bd794749dad4862` |
| `config-7.1.3+deb14.xz` | `config-7.1.3+deb14` | `df0fa920ad9a…` (`xvuklsmr/1`) | `d19647cff844…` | 296,281 | `fe4eebd17ea5a8c156f17f82dae2a7bda1e4f422bec5f31625aa6187eb20a470` |
| `mise.toml.recovered` | `mise.toml` | `c42db7c6d0a5…` (`xvuklsmr`) | `95d23b86953c…` | 24 | `d0581adc5b807ca4435e90925e787c8f22d8fbefc289771e0653757c2d7a1b9c` |

`df0fa920` = hidden prior working-copy commit, parent `66498c75b4f8` (Aug 24
master, bookmarked `matt7.1`), author/committer 2026-09-15. `c42db7c6` = the
mixed dirty-tree snapshot captured 2026-10-01 06:16 before jj reconciled the
tree clean at HEAD `587858367581` (v7.3-rc3-60). `mise.toml.recovered` is a
byte-for-byte copy, kept plain and **not** restored into any live tree; content
is exactly:

```toml
[tools]
rust = "latest"
```

## Compression and verification

The `.xz` files are deterministic: `xz` containers carry no timestamps, and
Python `lzma` (liblzma) was run single-threaded with fixed settings; two
compressions of the same input produced byte-identical output.

Reproduce:

```sh
python3 -c 'import lzma,sys; sys.stdout.buffer.write(lzma.compress(open("CONFIG","rb").read(), format=lzma.FORMAT_XZ, preset=9|lzma.PRESET_EXTREME))' < config-6.13-amd64 | sha256sum
```

Verify a snapshot against the table above:

```sh
xz -dc config-6.13-amd64.xz | sha256sum
```

Recorded checks at preservation time (both methods agree — Python `lzma`
round-trip and `xz -dc` CLI decode):

| file | decompressed sha256 | matches raw |
|---|---|---|
| `config-6.13-amd64.xz` | `83173838c8958d2166856f910463dfece727026cbd4712d57bd794749dad4862` | ✅ |
| `config-7.1.3+deb14.xz` | `fe4eebd17ea5a8c156f17f82dae2a7bda1e4f422bec5f31625aa6187eb20a470` | ✅ |

xz metadata: single block, CRC64, presets 9e (`xz -l` reports 56.3/58.5 KiB).

## Deliberately not included

- `MAKE.sh`, `LIQUORIX-SELECT.sh`, `config-debian-plus` — also present in
  `df0fa920`, but duplicates of files already canonical here
  (`MAKE.sh`, `config-debian-plus`) and in `/usr/local/src/LIQUORIX-SELECT.sh`.
- The in-tree kernel `.config` family, `certs/signing_key.pem`, build outputs —
  live in `/usr/local/src/linux` and are out of scope for this bundle; no
  private key material is committed anywhere in this directory.

Review details (facts vs. inference, op-log timeline): git-ignored scratch
`.test-agent/linux-source-assessment/fx-review.md` in the compfuzor checkout.
