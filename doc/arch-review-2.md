# Architecture review follow-up

This note captures the next review pass on the architecture model.

The previous review moved the architecture toward a runtime domain container.
This review sharpens that model further so it better matches compfuzor's actual
shape.

## Review summary

The `DOMAIN_META` / `DOMAIN` direction improved control flow, but the model was
still carrying three problems:

- `syn` on the runtime object felt low-value and denormalized in many cases
- `DOMAIN` was not the best container name because it competes with the label
  word `domain`
- the architecture was losing too much of the label/facet system while trying to
  improve runtime state organization

This review accepts a cleaner model.

## Accepted naming shift

Replace:

- `DOMAIN_META`
- `DOMAIN`

With:

- `REGISTRY`
- `SUBSYSTEMS`

### `REGISTRY`

`REGISTRY` is the registry of subsystem types.

It describes reusable subsystem definitions, labels, and bypass behavior.
It is not the runtime state container.

Example:

```yaml
REGISTRY:
  kernel_sysctl:
    labels:
      domain: kernel
      apply: sysctl
      effect:
        - host.fs
        - host.kernel
    bypass_vars: true
```

### `SUBSYSTEMS`

`SUBSYSTEMS` holds runtime subsystem instances.

Important rule:

- `SUBSYSTEMS` entries are freely named runtime instances
- they often correspond 1:1 with a registry entry, but they do not have to
- a subsystem may optionally declare `meta` to say which registry entry it uses

Example:

```yaml
SUBSYSTEMS:
  kernel_sysctl:
    meta: kernel_sysctl
    status: active
    requested: true
    bypassed: false
    valid: true
    active: true
    reasons: []
    spec:
      vm.swappiness: "180"
```

This opens space for multiple instances of one subsystem type when that becomes
useful.

## Accepted artifact-model shift

Drop `syn` as the default runtime artifact field.

Preferred subsystem fields are now:

- `norm`
- `spec`
- `contrib`

Meaning:

- `norm` is normalized subsystem input
- `spec` is the primary subsystem contract
- `contrib` is what the subsystem contributes to shared synthesis

Example:

```yaml
SUBSYSTEMS:
  get_urls:
    meta: get_urls
    status: active
    requested: true
    bypassed: false
    valid: true
    active: true
    reasons: []
    spec:
      - url: https://example.invalid/file.tar.gz
        dest: /opt/file.tar.gz
    contrib:
      BINS:
        - name: get-urls.sh
```

This is clearer than `syn` because it separates:

- the subsystem's own contract (`spec`)
- the subsystem's contributions to shared pipeline artifacts (`contrib`)

## Accepted bypass resolution shift

`bypass_vars` should support a compact default mode.

Accepted meaning:

- `bypass_vars: true` means "use the normal automatic bypass rules"

For a subsystem like `kernel_sysctl`, automatic bypass resolution should include:

- `KERNEL_SYSCTL_BYPASS`
- `KERNEL_BYPASS`

That means the helper should resolve bypass vars from several sources:

1. subsystem-specific default derived from subsystem id
2. domain-level default derived from labels such as `domain: kernel`
3. any explicit override list when `bypass_vars` is a list

Example:

```yaml
REGISTRY:
  kernel_sysctl:
    labels:
      domain: kernel
      apply: sysctl
    bypass_vars: true
```

Expected effective bypass sources:

- `KERNEL_SYSCTL_BYPASS`
- `KERNEL_BYPASS`

For `get_urls`, automatic bypass resolution would mean:

- `GET_URLS_BYPASS`

### Accepted helper contract

The architecture should assume a helper that:

1. resolves the subsystem id
2. reads `meta` when present
3. loads registry labels and bypass settings
4. derives subsystem-level bypass var names automatically when `bypass_vars` is
   `true`
5. derives domain-level bypass var names automatically when a domain label is
   present
6. computes `requested`, `bypassed`, `valid`, `active`, `status`, and `reasons`
7. creates `SUBSYSTEMS.<name>` only when requested

## Accepted label-system restoration

The label system remains important and should stay visible in the architecture.

The rewrite toward runtime containers should not erase that work.

Recommended interpretation now:

- prefixes and facets classify files, facts, and transport forms
- registry labels classify subsystem types
- runtime subsystem objects hold evaluated state and subsystem-owned artifacts

This keeps both useful models:

- label/facet architecture for classification
- structured runtime containers for control flow and data access

## Accepted kernel split

Kernel should not be modeled as one overloaded subsystem.

Instead use separate subsystem types:

- `kernel_modprobe`
- `kernel_sysctl`
- `kernel_sysfs`
- `kernel_all`

### `kernel_all`

`kernel_all` is the accepted wrapper subsystem.

Its role is to assemble the aggregate behavior that spans the narrower kernel
subsystems, especially the final `build.sh` and `install.sh` orchestration.

This lets the narrower kernel subsystems stay clean while still allowing one
higher-level orchestration point.

Example intent:

```yaml
REGISTRY:
  kernel_all:
    labels:
      domain: kernel
      apply: kernel-all
      role:
        - orchestration
    bypass_vars: true
```

## Rewrite implications for `doc/arch.md`

The next architecture rewrite should:

- replace `DOMAIN_META` with `REGISTRY`
- replace `DOMAIN` with `SUBSYSTEMS`
- remove `syn` as the default subsystem artifact field
- make `spec` primary and `contrib` the shared-synthesis field
- formalize `bypass_vars: true` as the default automatic bypass mode
- formalize subsystem-level and domain-level bypass auto-discovery
- restore label and facet content as first-class architecture material
- model kernel as several subsystem types plus `kernel_all`

## Outcome

This review locks in the next conceptual model:

- `REGISTRY` describes subsystem types
- `SUBSYSTEMS` holds requested runtime instances
- `spec` is the primary subsystem contract
- `contrib` carries shared-artifact contributions
- automatic bypass resolution should include both subsystem and domain gates
