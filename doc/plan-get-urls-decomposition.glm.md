# get_urls Decomposition Plan

## Current State

Two files, two phases:

| File | Kind | Phase | What it does |
|---|---|---|---|
| [`vars_get_urls.tasks`](../tasks/compfuzor/vars_get_urls.tasks) | `vars` | compile | Registers `get-urls.sh` as a BINS entry with generated shell body |
| [`fs_get_urls.tasks`](../tasks/compfuzor/fs_get_urls.tasks) | `fs` | fs-apply | Downloads each URL via `get_url`, writes `.url` sidecar files |

Data flow today:
```
GET_URLS (list of strings or mappings)
  → vars_get_urls: registers refresh script in BINS
  → fs_get_urls: downloads, writes .url sidecars
```

## Problem

`vars_get_urls` is not foundation. It generates a bin script body. That is
synthesis work hidden behind a `vars_` prefix. The script registration also
happens at a different semantic layer than the actual download execution.

## Proposed Decomposition

Three files across three semantic layers:

### `fn_get_urls.tasks` — Transform

| Facet | Value |
|---|---|
| kind | `fn` |
| class | `transform` |
| phase | `compile` |
| effect | `none` |
| apply | `get-urls` |

Responsibility: normalize `GET_URLS` into a uniform spec. No host effects. No
bin registration. Pure data shaping.

What it would do:
- Accept `GET_URLS` as strings or mappings (current mixed format)
- Produce a normalized list where each entry has explicit `url`, `dest`, `owner`, `group`, `validate_certs`
- Emit the result as `_fn_get_urls_out` (envelope)

Example fact output:
```yaml
_fn_get_urls_out:
  - url: "https://example.com/file.tar.gz"
    dest: "/opt/myapp/file.tar.gz"
    validate_certs: true
  - url: "https://other.com/bin"
    dest: "/opt/myapp/bin"
    validate_certs: false
```

This is extraction of the normalization logic that currently lives inline in
`fs_get_urls.tasks` via `_url`/`_dest` vars.

### `gen_get_urls.tasks` — Synthesis

| Facet | Value |
|---|---|
| kind | `syn` |
| class | `synthesis` |
| phase | `compile` |
| effect | `none` |
| apply | `get-urls` |

Responsibility: consume the normalized spec, synthesize bin registration and
any derived artifacts. This is where the `get-urls.sh` script registration
moves to.

What it would do:
- Read `_fn_get_urls_out`
- Register `get-urls.sh` in BINS (the refresh script, currently in `vars_get_urls`)
- Register any `.url` sidecar metadata if needed
- Emit `_syn_get_urls` envelope if downstream needs a handoff signal

This moves the generative `BINS` registration out of `vars_` into explicit
`gen_` synthesis.

### `fs_get_urls.tasks` — Execution (mostly unchanged)

| Facet | Value |
|---|---|
| kind | `fs` |
| class | `execution` |
| phase | `fs-apply` |
| effect | `host.fs` |
| apply | `get-urls` |

Responsibility: perform the actual downloads. Consumes the normalized spec
from `_fn_get_urls_out` instead of re-parsing `GET_URLS` inline.

Changes from current:
- Loop over `_fn_get_urls_out` instead of `GET_URLS|arrayitize`
- Remove inline `_url`/`_dest` normalization (moved to `fn_get_urls`)
- Still writes `.url` sidecars (this is an fs concern: recording provenance
  alongside the downloaded file)

## Data Flow

```
GET_URLS (raw input from playbook)
  │
  ▼
fn_get_urls.tasks
  normalize → _fn_get_urls_out
  │                    ▲
  │                    │
  ▼                    │
gen_get_urls.tasks     │
  synthesize BINS,     │
  emit _syn_get_urls   │
  │                    │
  ▼                    │
fs_get_urls.tasks ─────┘
  download, write .url sidecars
```

## .includes Wiring

Current:
```yaml
# in compile block:
- import_tasks: compfuzor/vars_get_urls.tasks
  tags: ['vars', 'always']

# in fs-apply block:
- import_tasks: compfuzor/fs_get_urls.tasks
  when: GET_URLS is defined and not GET_URLS_BYPASS|default(False)
```

Proposed:
```yaml
# in compile block (sub-stages in order):
- import_tasks: compfuzor/fn_get_urls.tasks
  when: GET_URLS is defined
  tags: ['vars', 'always']
- import_tasks: compfuzor/gen_get_urls.tasks
  when: GET_URLS is defined
  tags: ['vars', 'always']

# in fs-apply block (unchanged):
- import_tasks: compfuzor/fs_get_urls.tasks
  when: GET_URLS is defined and not GET_URLS_BYPASS|default(False)
```

## Migration Path

1. Create `fn_get_urls.tasks` — extract normalization from `fs_get_urls`
2. Create `gen_get_urls.tasks` — move BINS registration from `vars_get_urls`
3. Slim `fs_get_urls.tasks` — consume `_fn_get_urls_out`
4. Remove `vars_get_urls.tasks`
5. Update `.includes` wiring

Steps 1-3 can be done incrementally. Old and new can coexist during migration
by having `fs_get_urls` accept either `_fn_get_urls_out` or raw `GET_URLS`.

## Playbook Impact

None. `zswap.etc.pb` style playbooks stay exactly the same:

```yaml
GET_URLS:
  - https://example.com/some-file
```

The decomposition is internal to the pipeline. Playbooks declare `GET_URLS`
and nothing else changes.
