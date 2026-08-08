# status-ramoops.sh -- the one ramoops health check nothing else covers.
#
# The rest is already reusable elsewhere: status-modules.ts covers the
# pstore/ramoops *param* drift (pstore.backend, ramoops.mem_address, ...),
# status-cmdline.ts covers the raw memmap= token, and status-dirs.sh surfaces
# /sys/fs/pstore. What only a ramoops-aware check can assert is the kernel log:
# a CLEAN registration -- "Registered ramoops" and NOT "already in use" (the
# latter means efi_pstore grabbed the backend slot and ramoops silently failed,
# which the param checks won't catch since ramoops still loads).
#
# Contributed explicitly by pstore.etc.pb through BINS.
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-applicable.

_drift=0
_layout_complete=0
_say() { printf '%-12s %s\n' "$1" "$2"; }

# Ramoops can register with no dmesg records when optional regions consume the
# entire reservation. Check the effective boot parameters because registration
# alone cannot reveal that unusable layout. RAMOOPS_CMDLINE is a test seam.
_cmdline="${RAMOOPS_CMDLINE:-$(</proc/cmdline)}"
_cmdline_param() {
  local _key="$1" _token
  for _token in $_cmdline; do
    if [[ "$_token" == "$_key="* ]]; then
      printf '%s\n' "${_token#*=}"
      return 0
    fi
  done
  return 1
}
_uint() {
  if [[ "$1" =~ ^0[xX]([0-9a-fA-F]+)$ ]]; then
    printf '%u\n' "$((16#${BASH_REMATCH[1]}))"
  elif [[ "$1" =~ ^[0-9]+$ ]]; then
    printf '%u\n' "$((10#$1))"
  else
    return 1
  fi
}

if _mem="$(_uint "$(_cmdline_param ramoops.mem_size)")" \
  && _record="$(_uint "$(_cmdline_param ramoops.record_size)")" \
  && _console="$(_uint "$(_cmdline_param ramoops.console_size)")" \
  && _ftrace="$(_uint "$(_cmdline_param ramoops.ftrace_size)")" \
  && _pmsg="$(_uint "$(_cmdline_param ramoops.pmsg_size)")"; then
  _optional=$((_console + _ftrace + _pmsg))
  _layout_complete=1
  if ((_record == 0)); then
    _say layout "DRIFT: ramoops.record_size is zero"; _drift=1
  elif ((_mem < _optional)); then
    _say layout "DRIFT: optional regions ($_optional bytes) exceed mem_size ($_mem bytes)"; _drift=1
  else
    _dmesg=$((_mem - _optional))
    _records=$((_dmesg / _record))
    if ((_records == 0)); then
      _say layout "DRIFT: no dmesg records ($_dmesg bytes remain; record_size=$_record)"; _drift=1
    else
      _say layout "OK: $_dmesg dmesg bytes, $_records record(s) of $_record bytes"
    fi
  fi
else
  _say layout "n/a: complete ramoops size parameters not present on kernel cmdline"
fi

if [[ -v RAMOOPS_KLOG ]]; then
  _klog="$RAMOOPS_KLOG"
elif command -v journalctl >/dev/null 2>&1; then
  _klog="$(journalctl -k --no-pager 2>/dev/null || true)"
else
  _klog=""
fi

# memmap=$ reservations are trusted by the kernel, even if the selected range
# was MMIO in the firmware map. Validate against the original BIOS E820 lines,
# not /proc/iomem (which already reflects the user-modified map).
if ((_layout_complete)) && _address="$(_uint "$(_cmdline_param ramoops.mem_address)")" \
  && ((_mem > 0)) && [ -n "$_klog" ]; then
  _region_end=$((_address + _mem - 1))
  _e820_re='BIOS-e820: \[mem 0x([0-9a-fA-F]+)-0x([0-9a-fA-F]+)\] usable'
  _saw_e820=0
  _inside_e820=0
  while IFS= read -r _line; do
    if [[ "$_line" =~ $_e820_re ]]; then
      _saw_e820=1
      _e820_start=$((16#${BASH_REMATCH[1]}))
      _e820_end=$((16#${BASH_REMATCH[2]}))
      if ((_address >= _e820_start && _region_end <= _e820_end)); then
        _inside_e820=1
        break
      fi
    fi
  done <<<"$_klog"

  if ((_inside_e820)); then
    _say firmware "OK: ramoops reservation lies inside original BIOS-e820 usable RAM"
  elif ((_saw_e820)); then
    _say firmware "DRIFT: ramoops reservation is outside original BIOS-e820 usable RAM"
    _drift=1
  else
    _say firmware "n/a: original BIOS-e820 usable ranges not present in kernel journal"
  fi
fi

if [ -n "$_klog" ]; then
  if printf '%s\n' "$_klog" | grep -q 'Registered ramoops'; then
    if printf '%s\n' "$_klog" | grep -q 'already in use'; then
      _say journal "DRIFT: 'Registered ramoops' BUT also 'already in use' -- efi_pstore stole the slot"; _drift=1
    else
      _say journal "OK: Registered ramoops, no 'already in use'"
    fi
  else
    _say journal "DRIFT: no 'Registered ramoops' this boot"; _drift=1
  fi
else
  _say journal "n/a: kernel journal not readable (run under root?)"
fi

exit $_drift
