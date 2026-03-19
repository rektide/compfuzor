# Systemd Tasks Refactoring Plan

## Goal

Replace the ansible-driven `systemd.tasks` → `systemd.unit.includes` flow with the bin-driven approach in `vars_systemd_unit.tasks`, where generated scripts do the actual installation work.

## Current State

### `systemd.tasks` → `systemd.unit.includes` (ansible-driven)

1. **Variables setup** - Complex jinja to compute:
   - Unit name (dedashed, with instance suffix `@`)
   - Scope (user vs system)
   - Paths: `_src`, `_dest`, `_link`, `_unit_dir`

2. **Create directories**
   - `{{ dest | dirname }}`
   - `SYSTEMD_UNIT_DIR`

3. **Template unit file**
   - Renders from `files/systemd.{{type}}` to `{{ETC}}/{{unit}}`

4. **Symlink to systemd unit dir**
   - `{{ _unit_dir }}/{{ link_unit }}` → `{{ dest }}`
   - Controlled by `SYSTEMD_LINK`

5. **Enable unit**
   - `systemctl --{{ SCOPE }} daemon-reload && systemctl --{{ SCOPE }} enable`

6. **.d directory handling**
   - Includes `fs_d.tasks`
   - Symlinks `.d` directory

### `vars_systemd_unit.tasks` (new bin-driven approach)

1. **Variables setup** ✓
2. **Adds `install-unit.sh` to BINS** ✓
3. **Generates `install-{type}[-user].sh` scripts** ✓
4. **MISSING: ETC_FILES entry for unit file content**

The generated scripts source `install-unit.sh` which expects:
- `etc/{{unit}}.{{type}}` to exist (the unit file content)
- Then handles symlinking + enabling

## Gaps

### 1. ETC_FILES Generation

Need to add an ETC_FILES entry that generates the systemd unit content from:
- `SYSTEMD_UNIT` - [Unit] section directives
- `SYSTEMD_SERVICES` / `SYSTEMD_SOCKETS` / `SYSTEMD_MOUNTS` / `SYSTEMD_DNSSDS` - type-specific sections
- `SYSTEMD_INSTALL` - [Install] section directives

### 2. Expand SYSTEMD_UNITTYPES_ALL

Current types:
- service
- socket
- dnssd
- mount

Need to add for full systemd support:
- **timer** - [Timer] section
- **path** - [Path] section  
- **slice** - [Slice] section
- **scope** - [Scope] section
- **target** - [Unit] only
- **network** - [Match], [Network], [Address], [Route], etc. → `/etc/systemd/network/`
- **netdev** - [Match], [NetDev], [Bridge], [VLAN], etc. → `/etc/systemd/network/`
- **link** - [Match], [Link] → `/etc/systemd/network/`
- **nspawn** - container specs
- **preset** - unit presets
- **tmpfiles** - tmpfiles.d
- **sysusers** - sysusers.d

### 3. Unit Type to Target Directory Map

Different unit types install to different directories:

```yaml
SYSTEMD_UNIT_DIRS:
  service: "{{ SYSTEMD_UNIT_DIR }}"           # /etc/systemd/system or ~/.config/systemd/user
  socket: "{{ SYSTEMD_UNIT_DIR }}"            # /etc/systemd/system or ~/.config/systemd/user
  mount: "{{ SYSTEMD_UNIT_DIR }}"             # /etc/systemd/system or ~/.config/systemd/user
  timer: "{{ SYSTEMD_UNIT_DIR }}"             # /etc/systemd/system or ~/.config/systemd/user
  path: "{{ SYSTEMD_UNIT_DIR }}"              # /etc/systemd/system or ~/.config/systemd/user
  dnssd: "{{ SYSTEMD_UNIT_DIR }}"             # /etc/systemd/system or ~/.config/systemd/user
  network: "{{ SYSTEMD_NETWORK_DIR }}"        # /etc/systemd/network
  netdev: "{{ SYSTEMD_NETWORK_DIR }}"         # /etc/systemd/network
  link: "{{ SYSTEMD_NETWORK_DIR }}"           # /etc/systemd/network
  nspawn: /etc/systemd/nspawn
  tmpfiles: /etc/tmpfiles.d
  sysusers: /etc/sysusers.d
```

### 4. Unit Section Mapping

Each unit type has different sections:

| Type | Sections |
|------|----------|
| service | [Unit], [Service], [Install] |
| socket | [Unit], [Socket], [Install] |
| mount | [Unit], [Mount], [Install] |
| timer | [Unit], [Timer], [Install] |
| path | [Unit], [Path], [Install] |
| slice | [Unit], [Slice] |
| scope | [Unit], [Scope] |
| network | [Match], [Network], [Address], [Route], [DHCP], etc. |
| netdev | [Match], [NetDev], [Bridge], [VLAN], [VXLAN], etc. |
| link | [Match], [Link], [Battery], etc. |
| dnssd | [Service] (mDNS/DNS-SD) |

## Implementation Plan

### Phase 1: Core ETC_FILES Generation

#### 1a. Define Type Configuration Map (in `vars/systemd.yaml`)

```yaml
SYSTEMD_TYPE_CONFIG:
  service:
    sections: [Service]
    var_suffix: SERVICES
    dir_map: system
  socket:
    sections: [Socket]
    var_suffix: SOCKETS
    dir_map: system
  mount:
    sections: [Mount]
    var_suffix: MOUNTS
    dir_map: system
  timer:
    sections: [Timer]
    var_suffix: TIMERS
    dir_map: system
  path:
    sections: [Path]
    var_suffix: PATHS
    dir_map: system
  slice:
    sections: [Slice]
    var_suffix: SLICES
    dir_map: system
    no_install: true
  scope:
    sections: [Scope]
    var_suffix: SCOPES
    dir_map: system
    no_install: true
  target:
    sections: []
    var_suffix: TARGETS
    dir_map: system
  automount:
    sections: [Automount]
    var_suffix: AUTOMOUNTS
    dir_map: system
  swap:
    sections: [Swap]
    var_suffix: SWAPS
    dir_map: system
  dnssd:
    sections: [Service]
    var_suffix: DNSSDS
    dir_map: system
    no_unit: true
  network:
    sections: [Match, Network, Address, Route, DHCP, DHCPv6, IPv6AcceptRA, NTP, DNS, DHCPServer, Bridge, RoutingPolicyRule, NextHop, CAN, QDisc]
    var_suffix: NETWORK
    dir_map: network
    no_unit: true
    no_install: true
  netdev:
    sections: [Match, NetDev, VLAN, MACVLAN, VXLAN, GENEVE, BOND, Bridge, Veth, Tun, Tap, WireGuard, WireGuardPeer, L2TP, MacSec, FooOverUDP, Tunnel, Vrf, Vti, Xfrm]
    var_suffix: NETDEV
    dir_map: network
    no_unit: true
    no_install: true
  link:
    sections: [Match, Link, SR-IOV]
    var_suffix: LINK
    dir_map: network
    no_unit: true
    no_install: true
  nspawn:
    sections: [Exec, Files, Network, Settings]
    var_suffix: NSPAWN
    dir_map: nspawn
    no_unit: true
    no_install: true
```

#### 1b. Add ETC_FILES Generation Task (in `vars_systemd_unit.tasks`)

```yaml
- name: 'Generate systemd unit ETC_FILES'
  set_fact:
    ETC_FILES: "{{ ETC_FILES|default([]) + [_etc_file] }}"
  when: _has_type and _install_allowed and not SYSTEMD_INSTALL_BYPASS|default(False)
  loop: "{{ _all_specs | selectattr('type', 'in', SYSTEMD_UNITTYPES) | list }}"
  vars:
    _type_config: "{{ SYSTEMD_TYPE_CONFIG[_unit_type] }}"
    _var_name: "SYSTEMD_{{ _type_config.var_suffix }}"
    _section_data: "{{ lookup('vars', _var_name, default={}) }}"
    _unit_section: |
      {% if not _type_config.no_unit|default(false) %}
      [Unit]
      {% for k, v in (SYSTEMD_UNIT|default({})).items() %}
      {{ k }}={{ v }}
      {% endfor %}
      {% endif %}
    _type_sections: |
      {% for section in _type_config.sections %}
      {% set section_key = _var_name ~ '_' ~ section %}
      {% set section_vars = lookup('vars', section_key, default={}) %}
      {% if section_vars or loop.first %}
      [{{ section }}]
      {% for k, v in (section_vars if section_vars else _section_data).items() %}
      {{ k }}={{ v }}
      {% endfor %}
      {% endif %}
      {% endfor %}
    _install_section: |
      {% if not _type_config.no_install|default(false) %}
      [Install]
      {% for k, v in (SYSTEMD_INSTALL|default({})).items() %}
      {{ k }}={{ v }}
      {% endfor %}
      {% endif %}
    _etc_file:
      name: "{{ _unit_filename }}"
      content: "{{ _unit_section ~ _type_sections ~ _install_section }}"
```

### Phase 2: Expand SYSTEMD_UNITTYPES_ALL

Update `vars/systemd.yaml`:

```yaml
SYSTEMD_UNITTYPES_ALL:
  - service
  - socket
  - mount
  - timer
  - path
  - slice
  - scope
  - target
  - dnssd
  - automount
  - swap
  - network
  - netdev
  - link
  - nspawn
```

Note: The `dir_map` field in `SYSTEMD_TYPE_CONFIG` replaces the separate `SYSTEMD_UNIT_DIR_MAP`.

### Phase 3: Update install-unit.sh

The script needs to handle different target directories based on unit type's `dir_map`:

```bash
# dir_map comes from SYSTEMD_TYPE_CONFIG[type].dir_map
# Values: system, network, nspawn

get_unit_dir() {
  local dir_map="${1:-system}"
  local scope="${2:-system}"
  
  case "$dir_map" in
    network) echo "/etc/systemd/network" ;;
    nspawn) echo "/etc/systemd/nspawn" ;;
    system)
      if [ "$scope" = "user" ]; then
        echo "${HOME}/.config/systemd/user"
      else
        echo "/etc/systemd/system"
      fi
      ;;
    *) echo "/etc/systemd/system" ;;
  esac
}

# In generated install scripts, set DIR_MAP from type config
# UNIT_DIR_MAP="network"  # for network/netdev/link types
# UNIT_DIR_MAP="system"   # for standard unit types
UNIT_DIR="${UNIT_DIR_MAP:-system}"
```

### Phase 4: Remove Debug Fail

Remove the `fail: msg=dratzzz` from `systemd.unit.includes:81` once migration is complete.

## Files to Modify

1. `tasks/compfuzor/vars_systemd_unit.tasks` - Add ETC_FILES generation
2. `vars/systemd.yaml` - Expand SYSTEMD_UNITTYPES_ALL, add SYSTEMD_UNIT_DIR_MAP
3. `files/systemd/install-unit.sh` - Handle multiple target directories
4. `tasks/systemd.unit.includes` - Remove debug fail, eventually deprecate

## Testing

1. Verify existing playbooks like `pw-loopback.srv.pb` continue to work
2. Test user-scope units
3. Test network units install to correct directory
4. Verify symlinking and enabling work correctly via scripts

---

## UNIT_VARS and SYSTEMD_VARS_ROOT Documentation

### Overview

The `files/systemd.unit` template supports two modes for sourcing systemd configuration data:

1. **Top-level mode** (default): All `SYSTEMD_*` variables are read from the playbook's top-level vars
2. **Nested mode**: Variables are read from a nested dict, enabling multiple unit definitions in a single playbook

### Variables

| Variable | Defined In | Purpose |
|----------|------------|---------|
| `SYSTEMD_VARS_ROOT` | Playbook vars | String naming a top-level variable to use as the root dict for unit data |
| `UNIT_VARS` | `vars_systemd_unit.tasks` | The actual dict passed to the template (computed from `SYSTEMD_VARS_ROOT`) |

### How It Works

In `vars_systemd_unit.tasks:39`:
```yaml
UNIT_VARS: "{{ lookup('vars', SYSTEMD_VARS_ROOT, default=omit) if SYSTEMD_VARS_ROOT is defined else omit }}"
```

In `files/systemd.unit:22`:
```jinja
{%- set _root = UNIT_VARS|default(vars) -%}
```

The template then uses a fallback pattern for each data source:
```jinja
{%- set _unit_data = _root.SYSTEMD_UNIT if _root.SYSTEMD_UNIT is defined else SYSTEMD_UNIT|default({}) -%}
{%- set _main_section_data = _root[_main_section_key] if _root[_main_section_key] is defined else lookup('vars', _main_section_key, default={}) -%}
```

### Top-Level Mode (Backward Compatible)

When `SYSTEMD_VARS_ROOT` is **not** defined:
- `UNIT_VARS` = `omit`
- `_root` = `vars` (all top-level playbook variables)
- `_root.SYSTEMD_SERVICES` → top-level `SYSTEMD_SERVICES`
- Fallback `lookup('vars', 'SYSTEMD_SERVICES')` → top-level `SYSTEMD_SERVICES`

**Result**: Defining `SYSTEMD_SERVICES` at the top level continues to work as before.

### Nested Mode (Multiple Units)

To define multiple units of the same type in one playbook:

```yaml
myMount:
  SYSTEMD_UNIT:
    Description: Data partition mount
  SYSTEMD_MOUNTS:
    What: /dev/sda1
    Where: /mnt/data
    Type: ext4

myAutoMount:
  SYSTEMD_UNIT:
    Description: Auto-mount trigger
  SYSTEMD_AUTOMOUNTS:
    Where: /mnt/data
    TimeoutIdleSec: 300
```

Then invoke the tasks twice with different roots:
```yaml
- include_tasks: compfuzor/vars_systemd_unit.tasks
  vars:
    SYSTEMD_VARS_ROOT: myMount
    SYSTEMD_MOUNT: myMount

- include_tasks: compfuzor/vars_systemd_unit.tasks
  vars:
    SYSTEMD_VARS_ROOT: myAutoMount
    SYSTEMD_AUTOMOUNT: myAutoMount
```

### Current Gap

The current implementation in `vars_systemd_unit.tasks` does **not** loop over multiple `SYSTEMD_VARS_ROOT` values. To generate multiple units, the playbook must explicitly include the task multiple times. Future enhancement could support:
```yaml
SYSTEMD_VARS_ROOTS: [myMount, myAutoMount]
```
with a loop in the task.
