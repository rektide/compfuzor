# Architecture review

This note records a review of the current architecture writeup and the accepted
direction for the next rewrite.

Its purpose is simple: capture the review while it is still fresh, then use it
as the contract for the next architecture draft.

## Review summary

The previous `doc/arch.md` had the right ingredients, but not the right shape.

Main issues called out in review:

- it read like accumulated fragments rather than one coherent document
- it spent time explaining surrounding documents and historical transitions
  instead of standing on its own
- the introduction did not give a strong mental model or clear entry points
- the document mixed principles, reference material, migration advice, and
  examples without clean seams
- it kept reintroducing terminology-transition material that the project is
  trying to stop carrying forward

The rewrite should behave like one document with one spine, not a merge of old
notes.

## Accepted structural shift

The architecture document should be organized around clear layers and seams:

1. what compfuzor is doing at a high level
2. what layers make that work possible
3. what contracts exist between those layers
4. what naming and data shapes realize those contracts
5. what concrete domains look like when modeled correctly

That implies a cleaner structure:

- introduction and mental model first
- lifecycle and activation contracts early
- reference tables after the core model is established
- worked examples after the reference, not as scaffolding for it

## Accepted domain model shift

The review accepted a shift toward two shared containers:

- `DOMAIN_META` for static per-domain metadata
- `DOMAIN` for evaluated runtime domain state

### `DOMAIN_META`

`DOMAIN_META.<domain>` holds static metadata used to reason about a domain.

Minimum intended fields:

- `apply`
- `bypass_vars`

Example:

```yaml
DOMAIN_META:
  get_urls:
    apply: get-urls
    bypass_vars:
      - GET_URLS_BYPASS
```

Default bypass behavior:

- if no bypass list is declared, the default should be `<DOMAIN>_BYPASS`
- the helper that resolves bypass state should be able to derive that default

### `DOMAIN`

`DOMAIN.<domain>` is the runtime container for a requested domain.

Important rule:

- only create `DOMAIN.<domain>` if that domain is requested
- absence of `DOMAIN.<domain>` means the domain was not requested

Minimum intended fields:

- `status`
- `requested`
- `bypassed`
- `valid`
- `active`
- `reasons`

Recommended artifact fields by convention:

- `norm`
- `spec`
- `syn`

Example:

```yaml
DOMAIN:
  get_urls:
    status: active
    requested: true
    bypassed: false
    valid: true
    active: true
    reasons: []
    spec:
      - url: https://example.invalid/file.tar.gz
        dest: /opt/file.tar.gz
```

## Accepted artifact-direction shift

The review accepted moving toward domain-scoped artifacts where practical.

Preferred shape:

- `DOMAIN.get_urls.norm`
- `DOMAIN.get_urls.spec`
- `DOMAIN.get_urls.syn`

Instead of relying on global facts such as:

- `norm_get_urls`
- `spec_get_urls`
- `_syn_get_urls`

This is not a rejection of prefixes as a classification model. Prefixes still
matter as architectural vocabulary. The shift is about where public runtime
state lives.

Recommended interpretation:

- prefixes remain the semantic naming model
- `DOMAIN.<domain>.*` becomes the preferred runtime access path for domain data

Shared merged artifacts such as `BINS` or `ETC_FILES` are different. They are
cross-domain pipeline outputs and should not be forced under one domain.

## Accepted control-flow shift

The architecture should stop encouraging free-standing status facts such as
`GET_URLS_STATUS`.

Preferred shape:

- `DOMAIN.get_urls.status`
- `DOMAIN.get_urls.active`
- `DOMAIN.kernel.bypassed`

That gives the system one clear control-plane namespace instead of many global
status variables.

## Accepted helper direction

The review also accepted the need for a helper that resolves domain bypass and
activation state.

That helper should:

- take the domain id
- resolve bypass vars from `DOMAIN_META.<domain>.bypass_vars`
- default to `<DOMAIN>_BYPASS` if no list is declared
- determine whether the domain is requested
- compute `requested`, `bypassed`, `valid`, `active`, and `status`
- create `DOMAIN.<domain>` only when the domain is requested

This helper belongs to the control-plane side of the architecture.

## Rewrite implications for `doc/arch.md`

The next rewrite should do the following:

- remove document-history and document-transition framing
- remove terminology-transition bridge material
- introduce compfuzor as a system, not as a document cleanup effort
- formalize `DOMAIN_META` and `DOMAIN` as the main domain control model
- describe `spec`, `norm`, and `syn` as fields on domain objects by convention
- keep shared-artifact synthesis separate from per-domain state
- give worked examples in terms of `DOMAIN.get_urls.*` and `DOMAIN.kernel.*`

## Outcome

This review does not finalize every detail, but it does lock in the main shift:

- one cleaner architecture document
- one clearer runtime domain model
- one stronger separation between domain state and shared synthesized artifacts
