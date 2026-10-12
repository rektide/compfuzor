---
type: AdoptionEvidence
title: Proxy-first ENV CONFIG adoption, with normal Zim import
description: Concrete service/client selection and runtime-default policy; isolated verification and lessons before wider fuze work.
resource: /design/fuzings/proxy0.gpt61sol.md
status: draft
generated: {by: 'model:openai/gpt-6.1-sol#xhigh', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed1c4aafeffectZuEW8rySlAgl
    title: lucky-engine — adopt ENV CONFIG for the proxy, preserve invocation and shell defaults, and verify isolated normal Zim import
  - resource: /doc/config/definitions.md
    title: Complete CONFIG and literal env.d baseline, including projection and execution-context boundaries
  - resource: /design/fuzings/checkpoint0.gpt61sol.md
    title: Experimental native-root resolver deliberately excluded from this adoption
  - resource: /design/fuzings/contract1.gpt6a.md
    title: Native service/client contributions and normal ZIM ownership
  - resource: /design/fuzings/implementation0.gpt6a.md
    title: Independent CONFIGs before broad type integration
  - resource: /opencode-bus-proxy.src.pb
    title: Current proxy declarations, conditional priority environment, user unit, and import operation
  - resource: /vars/opencode.yaml
    title: Existing cross-playbook port, discovery, and watcher defaults, unchanged
  - resource: /files/opencode-bus-proxy/opencode-proxy-env.zsh
    title: Preserved runtime URL and native argument-default policy
  - resource: /files/_helpers/env
    title: Bound execution context with the existing envdefault preference restored
  - resource: /tests/integration/proxy_env_adoption.test.py
    title: Actual playbook render, selected assembly, shell sourcing, and isolated normal Zim import fixture
  - resource: file:///home/rektide/src/envdefault/envdefault
    title: Existing set-variable snapshot policy, including intentionally empty invocation values
  - resource: file:///home/rektide/src/opencode-working/packages/cli/src/args/environment.ts
    title: Native environment-argument preparation and explicit-argument suppression
  - resource: https://opencode.ai/v2/docs/cli
    title: V2 explicit server and standalone CLI behavior
---

# Adopted relationship

This adopts the reviewed baseline (`49950356`, `b7aa4e44`, `08b90300`) documented
in [independent CONFIGs and env.d](/doc/config/definitions.md), rather than reopening it.

The proxy now owns **one complete ENV CONFIG**. It remains a normal Zim
**producer**, not a second Zim host. No fuzing descriptor, enrolled-root resolver,
new merger, or CONFIG candidate dependency feature is needed for this slice.

| Native input | Selected output | Consumer |
|---|---|---|
| `50-proxy-service.env` + `99-local-priority.env` | `env-projections/proxy-service.env` | Unit's required `EnvironmentFile` |
| `60-proxy-client.env` | `env-projections/proxy-client.env.export` | Existing phase-56 client module |
| Whole env.d collection, priority last | `env` / `env.export` | Generated command application defaults, **not** selective service/shell import |

The shared `vars/opencode.yaml` ports remain authoritative across playbooks.
One proxy listener expression supplies its service bind and client URL default.
The origin upstream remains fixed from the shared primary port. Discovery and
Effect-watch tasks still combine into ENV_PRIO; their switches, cooperate/stomp
mode, metadata flag, account password pointer, unit ordering, and restart policy
are not reimplemented. `SYSTEMD_ENV` still means manager publication.

Ordinary ENV can contain build/command knobs; the service selects only its named
contribution and priority input. Use ENV_PRIO for daemon overrides. Arbitrary
operator-authored priority keys are explicitly selected, not type-filtered;
putting client/internal keys there would deliberately give them to the daemon.
The default declarations inject neither client args nor execution plumbing.

# Runtime behavior, not just literal projection

The client contribution contains **only OPENCODE_PROXY_URL**, not a precomputed
OPENCODE_ARGS. The small native module retains the original policy:

- Empty **or** unset URL loads the literal client export; a nonempty runtime URL
  wins and is exported, including a previously unexported shell parameter.
- Empty **or** unset args become `--server <effective runtime URL>`; nonempty
  args are preserved. No function or alias wraps `opencode`.
- Native CLI argument preparation still gives explicit `--server` and
  `--standalone` authority. This requires the selected build's native args support;
  this adoption does not build or install that build.
- Missing projection fails when a default is needed. A deliberate URL override
  does not need the default file. No independently rendered fallback endpoint
  masks incomplete assembly.

Generic env-zsh intentionally preserves empty parameters. Using it unconditionally
here would change the user's module semantics; a gated env-export plus native
derived args is the smaller faithful adapter.

The normal render lane would otherwise run Rust before CONFIG's canonical build.
`build-proxy-env.sh` calls the existing bound ENV worker before generated Rust bins,
and joins ordinary build.sh at the identity/prepare phase before Rust's main phase. It has
no application ENV helper, so assembly bootstraps without its own output.

The proxy also adds an ordinary `early` prerequisite to its generated
`install-zimfw.sh`: canonical ENV assembly runs before normal host import/cache
construction. Normal rendering also assembles ENV. BINS_RUN_BYPASS can therefore
skip daemon builds while a later explicit importer still assembles its prerequisite.
Standalone service updates can use:

```sh
<proxy>/bin/config-assemble.sh --definition env --context canonical
ZIM_HOST_DIR=<host> <proxy>/bin/install-zimfw.sh
```

Assembly and host import are separate transactions. An ENV failure prevents the
import; a later import failure does not undo successfully assembled producer ENV.
This is explicit source ordering, not a candidate DAG or service restart request.

The opt-in generated ENV helper had directly sourced env.export, bypassing the
legacy envdefault preference. It now uses that same existing preference, then
restores env.context. Installed envdefault preserves set values, even empty ones;
DIR/NAME/etc remain bound regardless of foreign invocation or authored app values.
The preexisting direct-source fallback when envdefault is unavailable is retained,
not upgraded into a new defaulting engine.

# Evidence and limits

The fixture runs the actual playbook through local Ansible with every writable
hierarchy/account path redirected and package, repository, build, unit activation,
and global-link effects bypassed. It runs the real ENV transaction worker and
normal Zim host/producer importer, using vendored zimfw and the existing
block-in-file executable. No daemon, OpenCode process, tmux pane, or real systemd
manager is changed.

Usability depends on the usual CONFIG runtime tools (Node, jq, Python) and, for
preserved invocation defaults, installed envdefault. The isolated host uses the
real vendored Zim controller, not a cache-writing test double.
It seeds one harmless local module per host channel: the real controller rejects
empty channels. No remote module installation or extra production host is introduced.

Targeted commands:

```sh
ansible-playbook opencode-bus-proxy.src.pb --syntax-check
python3 tests/integration/proxy_env_adoption.test.py
# config_definitions.test.py: test_env + test_current_proxy_priority_preservation
# opencode-working/packages/cli: bun test src/args/environment.test.ts
```

Verified on 2026-10-12: the complete adoption fixture and syntax check passed;
the targeted baseline ENV/context and proxy-priority regressions passed;
`tests/filter_plugins/env_compile.test.py` passed; native CLI argument tests
passed **22/22**. Python compilation and document links/provenance checks passed.
No TypeScript runtime code changed, so prior reported baseline type/lint/runtime
checks were trusted rather than repeated wholesale.

The adoption fixture covers four discovery/watch combinations, preserved priority
keys, default/custom ports, exact compiled input selection, application/execution
separation, actual Zsh defaults/overrides/empties/native args, missing projection,
repeat generation/assembly, build prerequisite order, and real isolated Zim import/cache sourcing. The Rust
operation's generated setup is exercised without executing its installer body.
Service assignment inspection uses simple fixture values; it is not a claim of
live systemd activation or a second general EnvironmentFile parser.

Retired optional files are deliberately retained. Exact service/client selections
exclude them; whole-collection env.export still includes active retained inputs.
Turning discovery/watch off regenerates the owned priority file rather than
pruning unrelated contributions. Source-time shell defaults are not managed refresh:
re-sourcing preserves nonempty args even if a URL later changes.

# What this teaches the next fuze decision

Native contributions plus existing assembly/import are already useful. Consumer
selection should name the files it actually wants; importing a whole producer ENV
would reintroduce command, service, and client cross-contamination. Literal shared
data and genuinely shell-derived behavior need different homes, not one universal
serializer. A concrete operation can own source order without another framework.

Normal Zim import links/copies channel declarations that still address the producer's
canonical module/projection. That is a live producer dependency, not a relocatable
copy of all client material. Existing-shell refresh, source/winner inspection,
portable material delivery, and general admission/status of enrolled roots remain
separate questions. The [native-root checkpoint](/design/fuzings/checkpoint0.gpt61sol.md)
stays experimental; the [descriptor pilot](/doc/fuzings/README.md) is predecessor
evidence, not the implementation path silently adopted here. Broader fuze work is
deferred to the parent's reassessment of this concrete experience.
