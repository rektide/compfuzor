---
type: VerificationReport
title: Standalone archive bundle verification
description: Final packaging, test-suite, and copied-bundle verification after archive source fixes.
status: draft
generated: { by: model:gpt6luna, at: 2026-09-28 }
sources:
  - id: archive-readme
    resource: /archive/README.md
    title: Archive toolkit operations and build contract
  - id: custody-guide
    resource: /doc/archive-toolkit/custody.md
    title: Archive custody operator and library guide
  - id: safety-review
    resource: /design/archive-toolkit/safety-review0.gpt6luna.md
    title: Archive custody safety review checkpoint
---

# Standalone archive bundle verification

## Scope and outcome

This report verifies the generated distribution artifact
[`archive/repo-jj-archive.ts`](/archive/repo-jj-archive.ts) against the Node 26
single-file contract, after the source cancellation and verifier safety fixes.
The final source commit in scope is
[`2063ca64`](https://github.com/rektide/compfuzor/commit/2063ca6442b571a618c5f8a5a21e4e0fb224d245).
Later commits visible during verification changed documentation only; no
archive source or test changes followed that source checkpoint.

**Outcome: the final bundle builds reproducibly and all requested checks,
source tests, integration tests, and copied-bundle probes pass.** The artifact
was committed separately as `a4860401` (`Rebuild standalone Node 26 archive
bundle`). This is a distribution verification, not a general production
signoff for custody operations; see the separate custody qualification and
review references below.

## Build and artifact evidence

Environment: Node `v26.6.0`, pnpm `11.9.0`.

- `pnpm check` passed: formatting matched across 66 files, lint reported zero
  warnings and zero errors across 83 files, and `tsgo --noEmit` passed.
- `pnpm build` passed twice after the source checkpoint. Both builds produced
  identical archive bytes:
  `6b7b2ba3d5da0027076c9f38725b09c4583881684872aca7201538a37f49c486`.
- The resulting file is 1,152,701 bytes, mode `0755`, ESM, and has no source
  map or code-split companion. Its executable imports are exclusively `node:`
  built-ins; bundled Effect dependencies are embedded in the file. It exports
  both `main` and `runExecutable`.
- The build also emitted `runtime/compfuzor-runtime.mjs`; that unrelated
  generated artifact had no diff and was not committed.

## Test results

| Command | Result |
|---|---|
| `pnpm check` | Passed |
| `pnpm build` | Passed twice; identical artifact hash |
| `node --test 'archive/test/**/*.test.ts'` | 127 passed, 0 failed |
| `pytest --import-mode=importlib -q tests/integration/repo_jj_archive.test.py tests/integration/archive_library.test.py tests/integration/archive_cli_contract.test.py tests/integration/archive_custody_cli.test.py` | 34 passed in 140.99s |

The Node tests include all six cancellation paths: SIGINT and SIGTERM against
the source entry, compatibility launcher, and copied standalone bundle. The
integration run includes the current
`test_runner_prefers_host_checkout_with_playbook_fallback` case; its fixture
has the `remote, seed` values defined and the complete module passed.

The first pytest attempt was bounded at 120 seconds and timed out before
completion. It made no code changes. The exact suite was rerun with a longer
timeout and completed with the passing result above.

## Copied-bundle probes

Disposable Git/jj fixtures were created under `/home/rektide/tmp-opencode`;
the temporary directory was removed afterward. The copied layout contained
the bundle and compatibility launcher, but no `archive/src`, `node_modules`,
or `package.json`.

- Executed the copied bundle's executable shebang under Node 26 (`--version`)
  successfully; stdout was `0.1.0` and stderr was empty. Dynamic import also
  confirmed callable `main` and `runExecutable` exports.
- Executed the copied compatibility launcher with its bundle fallback and no
  source or dependencies. `refresh --json` created a jj archive from a local
  fixture remote.
- Executed the copied bundle directly for custody planning and `adopt
  --apply`; the apply response reported verified custody. After moving the
  fixture source out of its original path, standalone `verify-adoption`
  succeeded with `custodyVerified: true` and `sourceDrift: "unknown"`, as
  expected when the source is absent.

When invoking a copied `.ts` bundle as `node <file>` beneath the ambient
`/home/rektide/package.json` (outside the copied layout), Node emitted its
non-fatal `MODULE_TYPELESS_PACKAGE_JSON` warning while auto-detecting ESM. The
operation succeeded; executing the artifact through its shebang suppresses
that warning via the existing Node flag. No package manifest was added to the
standalone layout.

## Interpretation and boundaries

These checks confirm that the current source can be distributed and run as a
single Node 26 TypeScript file, including the tested cancellation and custody
CLI entry paths. They used local disposable repositories only: no production
archive was inspected or modified. They do not broaden custody guarantees or
authorize source retirement. For those semantics, use the
[custody operator guide](/doc/archive-toolkit/custody.md) and its explicit
limitations; the independent [safety review checkpoint](/design/archive-toolkit/safety-review0.gpt6luna.md)
is separate from this packaging report.

## Cross-references

- [Archive README](/archive/README.md): canonical command surface, dual
  launcher resolution, Node 26 runtime contract, and build/test instructions.
- [Custody operator guide](/doc/archive-toolkit/custody.md): explains what
  `adopt` and `verify-adoption` establish and what they do not permit.
- [Custody safety review checkpoint](/design/archive-toolkit/safety-review0.gpt6luna.md):
  records independent source-read-only and acquisition-boundary findings;
  this report verifies bundle packaging rather than replacing that review.
