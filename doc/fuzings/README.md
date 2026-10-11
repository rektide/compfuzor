# Fuzings — declaration and inspection pilot

A fuze owns named composition actions. A constituent publishes a fuzing to an
exact deployment, fuze ID, and `user` or `system` scope. The initial implementation
renders declarations and produces read-only action plans. The schema is a proposal
being exercised, not an accepted general runtime contract.

See [the contract and intended OpenCode flow](/design/fuzings/contract0.gpt6a.md)
and [the initiating handoff](/design/fuzings/handoff0.gpt61s.md).

## Declare

```yaml
FUZE:
  id: example
  scope: user
  actions:
    refresh: {kind: zim-import, required: [client]}
    activate: {kind: shell-source}
    restart-dependencies: {kind: exec}

FUZINGS:
  - id: client
    target: {dir: /opt/example, fuze: example, scope: user}
    actions:
      refresh: {kind: zim-import, order: 50}
      activate: {kind: shell-source, order: 50, path: etc/client.zsh}
      restart-dependencies:
        kind: exec
        order: 50
        path: bin/restart.sh
        args: []
```

Each declaring playbook uses its usual `tasks/compfuzor.includes`. The new
`gen_fuzings.tasks` synthesizes ordinary `ETC_FILES`/`ETC_DIRS`; the existing
filesystem writer renders them:

| Artifact | Ownership and purpose |
|---|---|
| `etc/fuze.json` | Owner's ID, deployment, scope and supported action kinds |
| `etc/fuze.d/` | Native installed membership, initially empty |
| `etc/fuzings/<id>.json` | Constituent's exact target and per-action contributions |
| `etc/fuzings.json` | Closed index of this render's offered descriptors |

Declarations are resolved at Ansible task scope, including nested target paths
and numeric order variables. Invalid fields, unsafe IDs/paths, duplicate IDs,
noninteger orders, or malformed argument arrays fail compilation. Rendering writes
only the declaring deployment's artifacts and does not enroll constituents.

Explicit `FUZINGS: []` empties the offer index. It does not delete historical
descriptor files or remove existing membership references. Installed membership
remains authoritative until an operator changes it deliberately.

## Inspect a selected action

From the source checkout, using a Node version with native TypeScript support:

```sh
node files/fuzings/inspect.ts --deployment /opt/example refresh
```

This prints a JSON inspection plan. It validates membership and binds resource
paths; it executes no handlers and does not check whether those handlers or a ZIM
host are available. There is no deployed fuzing command alias yet.

Membership is an exact symlink:

```text
/opt/example/etc/fuze.d/client.json
  -> /opt/client/etc/fuzings/client.json
```

For this pilot, operators or fixtures create that link explicitly. The constituent
installation hook is the next slice. Descriptor homes are checked against the
declared constituent deployment, including Compfuzor's normal external `etc`
symlink. Inline JSON membership files fail validation.

- Rename a link to `<id>.json.disabled` to disable it, reverse to enable, unlink
  deliberately to remove membership. Rendering preserves these controls.
- Active broken references, duplicate active/disabled slots, wrong targets/scopes,
  mismatched IDs, and unknown/incompatible action joins fail planning.
- Disabled links remain visible even when their descriptor is unavailable.
- `required` is checked for the selected action: absent, disabled or nonparticipating
  required members fail. An action without requirements may have an empty plan.
- Invocations sort by explicit nonnegative integer `order`, then literal member ID.
  Membership alone does not select any other action.
- `exec` binds a `bin/` file plus literal argv; `shell-source` binds an `etc/` file;
  `zim-import` binds the constituent deployment for the existing ZIM importer.

The plan is a current inspection, not a stored execution authorization or filesystem
snapshot. A future executor must re-admit selection and verify execution prerequisites.

## Verification and next slice

The isolated render fixture uses `/home/rektide/tmp-opencode`, the local Ansible
connector, and the actual generator/artifact writer. Planner tests cover ordering,
action separation, missing/disabled/required members, instance/audience isolation,
descriptor ownership, and nonmutation. Run:

```sh
python3 tests/filter_plugins/fuzings.test.py
python3 tests/integration/fuzings.test.py
pnpm exec vitest run tests/fuzings/plan.test.ts
pnpm check:fuzings
pnpm check:type
```

Verified on 2026-10-11 in session `ses_ed3fd05d5ffeCPRCMwcAZY343U`: all three
compiler tests, seven planner tests, the isolated Ansible render fixture, and
the full `pnpm check` passed. Both `opencode.src.pb` and
`opencode-bus-proxy.src.pb` passed Ansible syntax checks.

The next implementation connects constituent installation through LINKS, native
ZIM refresh with incomplete/skip handling, and shell-local activation policy. Then
OpenCode and its proxy can adopt declarations and tested client restart ordering.
Their playbooks and live lifecycle behavior have not been integrated by this pilot.
The omnibus runtime was not rebuilt because its current source closure contains
unrelated unfinished registration changes.
