# Isolated native fixture helpers

[`fixtures.py`](/tests/integration/keybindings/fixtures.py) supplies portable USER/SYSTEM
provider+consumer policy pairs and complete HOME/XDG isolation. Generated fixtures
declare `KEYBINDING_REGISTRY_POLICY`; native and passive keybinding endpoints can
also select its emitted document through `--registry-policy PATH`.

- Both registry sides must be disposable before SYSTEM execution. A temporary native
  root or HOME alone does not isolate normal `/var/lib`/`/etc` registries.
- Set XDG search directories as well as home roots; otherwise admission can see
  unrelated shared registrations.
- Separate producer owners use distinct IDs. A same-ID foreign reference is an
  ownership conflict, not a reason to bypass registry checks.
- Full playbook renders start fresh. Compfuzor intentionally doesn't prune stale
  launchers, so reused scratch directories cannot prove an obsolete entry is absent.
- Stub session-manager commands and reject privilege tools when authored bodies may
  run. HOME isolation does not isolate DBus.
- Keep deployment material, live native outputs and registry references separate.
  Native validators remain real unless a test explicitly isolates orchestration
  with fake validators.

The [generated registry proof](/tests/integration/registry_keybindings_generated.test.py)
extracts real playbook declarations/authored bodies and runs stock subtasks against
the bundled artifact; it is not full provisioning/default-placement evidence.
The [full-playbook host tests](/tests/integration/keybindings_consumer_hosts.test.py)
and [default-placement test](/tests/integration/action_placement.test.py) preserve
those separate acceptance paths. See the
[regression map](/design/registry-discovery/regression-map0.gpt61s.md) for retained
native/action semantics and evidence boundaries.
