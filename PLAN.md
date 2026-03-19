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

Add to `vars_systemd_unit.tasks`:

```yaml
- name: 'Generate systemd unit ETC_FILES'
  set_fact:
    ETC_FILES: "{{ ETC_FILES|default([]) + [_etc_file] }}"
  when: _has_type and _install_allowed and not SYSTEMD_INSTALL_BYPASS|default(False)
  loop: "{{ _all_specs | selectattr('type', 'in', SYSTEMD_UNITTYPES) | list }}"
  vars:
    _etc_file:
      name: "{{ _unit_filename }}"
      content: |
        [Unit]
        {% for k, v in (SYSTEMD_UNIT|default({})).items() %}
        {{ k }}={{ v }}
        {% endfor %}
        {{ _type_section }}
        [Install]
        {% for k, v in (SYSTEMD_INSTALL|default({})).items() %}
        {{ k }}={{ v }}
        {% endfor %}
    _type_section: >-
      {% if _unit_type == 'service' %}
      [Service]
      {% for k, v in (SYSTEMD_SERVICES|default({})).items() %}
      {{ k }}={{ v }}
      {% endfor %}
      {% elif _unit_type == 'socket' %}
      [Socket]
      {% for k, v in (SYSTEMD_SOCKETS|default({})).items() %}
      {{ k }}={{ v }}
      {% endfor %}
      {% elif _unit_type == 'mount' %}
      [Mount]
      {% for k, v in (SYSTEMD_MOUNTS|default({})).items() %}
      {{ k }}={{ v }}
      {% endfor %}
      {% endif %}
```

### Phase 2: Expand SYSTEMD_UNITTYPES_ALL

Update `vars/systemd.yaml`:

```yaml
SYSTEMD_UNITTYPES_ALL:
  # Standard unit types
  - service
  - socket
  - mount
  - timer
  - path
  - slice
  - scope
  - target
  - dnssd
  # Network unit types (install to /etc/systemd/network/)
  - network
  - netdev
  - link
  # Container
  - nspawn

SYSTEMD_UNIT_DIR_MAP:
  service: system
  socket: system
  mount: system
  timer: system
  path: system
  slice: system
  scope: system
  target: system
  dnssd: system
  network: network
  netdev: network
  link: network
  nspawn: nspawn
```

### Phase 3: Update install-unit.sh

The script needs to handle different target directories based on unit type:

```bash
get_unit_dir() {
  local unit_type="$1"
  local scope="$2"
  local dir_map="$3"
  
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
