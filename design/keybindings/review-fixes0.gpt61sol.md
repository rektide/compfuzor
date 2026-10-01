---
type: ReviewResolution
title: Empty producer membership and standalone worker dependencies
description: Resolve the two concrete review gaps without client cutover, live configuration changes or tool installation.
resource: /design/keybindings/review-fixes0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-01 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - resource: /design/keybindings/implementation2.gpt61sol.md
    title: Accepted author-facing machinery checkpoint
  - resource: /tests/integration/keybindings_empty_producer.test.py
    title: Actual populated-to-empty reinstall proof
  - resource: /tests/integration/keybindings_dependencies.test.py
    title: Bare render dependency metadata proof
---

# Resolved outcomes

The parent identified two real omissions before closing the machinery checkpoint.
Both are fixed and saved separately. No client migration, root adoption, live
configuration operation or opportunistic tool/package installation was performed.

## Empty producer remains a producer

Previously the manifest and install operation were inferred from `bool(resources)`.
That left an old manifest on disk and switched a populated-to-empty producer's
wrapper into host reassembly. Producer role is now declaration-driven:

- Explicit producer targets, or an ordinary producer without consumer profiles,
  retain producer role even when their resource list is empty.
- Rendering replaces `keybinding-producer.json` with `resources: []`.
- Each selected target wrapper still invokes producer installation, which replaces
  that group's exact membership with an empty list through the existing commit.
- An implicit consumer-only host remains host-only and emits no producer manifest.
- Stale source/native files are excluded, not pruned or rediscovered.

Code: [generator](/library/filter_plugins/keybindings_compile.py). Commit
**`3fc33181` — Preserve producer role and commit empty membership on reinstall**.

Verification: [unit coverage](/tests/filter_plugins/keybindings_compile.test.py)
and [real generated reinstall test](/tests/integration/keybindings_empty_producer.test.py)
passed. The integration renders two populated producers, empties one with the same
targets, re-renders/reinstalls it, and checks empty manifest/membership, removed
owned root blocks, preserved second producer and retained stale physical files
for both Niri and Umbriel.

## Standalone generation contributes stock worker packages

Ordinary CONFIG and standalone keybinding generation now share
`config_runtime_packages()` from [config_compile.py](/library/filter_plugins/config_compile.py).
Both contribute **`PKGS: [jq]`**. [The generator task](/tasks/compfuzor/gen_keybindings.tasks)
merges that package metadata uniquely, including bare hosts/producers without
ordinary CONFIGS. No apt invocation or unrelated provisioning behavior was added.

Commit **`94c63d7d` — Reuse CONFIG worker packages in standalone keybinding generation**.

Verification: compiler equality checks compare the keybinding contribution to
ordinary CONFIG publication; [render-only integration](/tests/integration/keybindings_dependencies.test.py)
passed and checks that bare host and producer metadata each contain jq exactly once.
Existing CONFIG compiler tests also passed.

Node and block-in-file are explicitly documented non-package prerequisites under
the existing convention, rather than invented apt dependencies:

- [package.json](/package.json) declares the compatible Node engine range.
  [nodesource.repo.pb](/nodesource.repo.pb) is the existing explicit nodejs provider.
- [block-in-file.src.pb](/block-in-file.src.pb) builds/promotes a standalone artifact
  and exposes a global command. `CONFIG_BLOCK_IN_FILE` can bind it, consistent with
  [Mise2](/mise2.opt.pb). The generator does not pretend it is an apt package.
- Explicitly selected native validators remain provided by compositor deployment;
  absent commands fail preparation rather than skipping validation.

The [maintained producer guide](/doc/config/keybinding-producers.md) now describes
empty reinstall semantics and the package/external-command distinction. The real
Niri host binding and deliberate Umbriel root adoption remain the next human
discussion before any client migration.
