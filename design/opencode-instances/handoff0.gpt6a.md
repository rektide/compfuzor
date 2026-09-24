---
type: ImplementationCheckpoint
title: Interrupted branch-specific OpenCode instance implementation
description: Preserve GX changes after provider quota exhaustion, without implying that deployment rendering or installation has passed acceptance.
resource: /design/opencode-instances/handoff0.gpt6a.md
tags: [opencode, instances, deployment, handoff]
status: draft
generated: { by: "openai/gpt-6-astra", at: 2026-09-24 }
---

# Interrupted GX work

GX session `ses_f2f87232fffeO84N8iRcY3i2Vi` was implementing branch/workspace-
specific OpenCode servers, distinct ports and shell entrypoints. It reached its
provider usage limit before a final checkpoint. The parent recovered this work
after a server restart; do not rerun the original implementation from scratch.

## Preserved files

- [`opencode.src.pb`](/opencode.src.pb): instance naming, source workspace,
  secondary endpoint/config/database settings and generated deployment surfaces.
- [`files/opencode/opencode-instance`](/files/opencode/opencode-instance): proposed
  secondary-instance launcher.
- [`files/opencode/opencode-service.zsh`](/files/opencode/opencode-service.zsh):
  instance-specific client-argument module resolution.
- [`tests/integration/opencode_instances.test.py`](/tests/integration/opencode_instances.test.py):
  unfinished isolated rendering and launcher verification.

These are a work-in-progress checkpoint, not a tested release or installation.
The last GX message concerned moving secondary environment additions to the
existing `ENV_PRIO` mechanism to avoid evaluating late-bound variables too early.
Recover exact test evidence and unresolved rendering errors from that session.

## Preserve concurrent work

At recovery the worktree also contained changes to `.beads/interactions.jsonl`,
`.beads/issues.jsonl`, and `tasks/compfuzor/sub_status_proc.tasks`. The parent has
not attributed those changes and excludes them from this checkpoint. Establish
ownership before editing or including them. Several unrelated commits landed in
this repository during the delegation; do not roll them back.

## Completion boundary

Inspect actual generated paths, late variable expansion, primary compatibility,
instance-specific `OPENCODE_ARGS`, source selection, credentials and database
settings. Finish isolated rendering/launcher tests and syntax checks before
claiming usability. Never run installation/thunks against the live services for
verification. Preserve the existing default instance and avoid implicit managed-
service election when clients select explicit servers.

The user allows considering a shared DB, but no active-active execution has been
authorized as an incidental test. Bus-smart adds no DB migration of its own;
process-local execution/recovery and event buses still make concurrent servers
on one DB problematic. Backups are a separate operation and not proof of safe
concurrent execution. The multiplexer architecture is a draft in the bus-smart
repo and must not be implemented as part of this deployment slice.
