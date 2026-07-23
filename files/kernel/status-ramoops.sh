# status-ramoops.sh -- verify ramoops/pstore is winning and healthy at runtime.
#
# Companion to status-modules.ts (which compares desired vs deployed vs live
# *values*): this checks the runtime actually honors them -- the pstore backend
# slot went to ramoops (not efi_pstore), the reserved region is recognized, the
# live cmdline carries the reservation, and the kernel log shows a clean
# registration. A non-empty /sys/fs/pstore is informational (a crash was
# captured), not drift.
#
# Contributed by the kernel_bls subsys (active for ramoops cmdline configs).
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-applicable.

_drift=0
_say() { printf '%-12s %s\n' "$1" "$2"; }

# 1. pstore backend slot = ramoops (efi_pstore wins this by default -> the
#    whole reason pstore.backend=ramoops + blacklist efi_pstore exist).
_be="$(cat /sys/module/pstore/parameters/backend 2>/dev/null || true)"
if [ "$_be" = "ramoops" ]; then
  _say backend "OK: ramoops"
else
  _say backend "DRIFT: '${_be:-<unset>}' (wanted ramoops -- efi_pstore likely stole the slot)"; _drift=1
fi

# 2. efi_pstore actually blacklisted / not loaded
if [ -d /sys/module/efi_pstore ]; then
  _say efi_pstore "DRIFT: still loaded (blacklist ineffective)"; _drift=1
else
  _say efi_pstore "OK: not loaded"
fi

# 3. ramoops recognized its reserved region (mem_address populated from cmdline)
_ma="$(cat /sys/module/ramoops/parameters/mem_address 2>/dev/null || true)"
if [ -n "$_ma" ]; then
  _say mem_address "OK: $_ma"
else
  _say mem_address "DRIFT: empty -- ramoops loaded without its cmdline params (reboot needed?)"; _drift=1
fi

# 4. live cmdline carries the reservation + backend pin
if grep -q 'memmap=' /proc/cmdline 2>/dev/null && grep -q 'pstore.backend=ramoops' /proc/cmdline 2>/dev/null; then
  _say cmdline "OK: memmap= + pstore.backend= present"
else
  _say cmdline "DRIFT: missing memmap= or pstore.backend= in /proc/cmdline (BLS not regenerated?)"; _drift=1
fi

# 5. kernel log: clean ramoops registration this boot
if command -v journalctl >/dev/null 2>&1; then
  _klog="$(journalctl -k --no-pager 2>/dev/null || true)"
  if [ -n "$_klog" ]; then
    if printf '%s\n' "$_klog" | grep -q 'Registered ramoops'; then
      if printf '%s\n' "$_klog" | grep -q 'already in use'; then
        _say journal "DRIFT: 'Registered ramoops' BUT also 'already in use'"; _drift=1
      else
        _say journal "OK: Registered ramoops, no 'already in use'"
      fi
    else
      _say journal "DRIFT: no 'Registered ramoops' this boot"; _drift=1
    fi
  else
    _say journal "n/a: kernel journal not readable (run under root?)"
  fi
else
  _say journal "n/a: journalctl unavailable"
fi

# 6. /sys/fs/pstore: empty in steady state; non-empty = a crash record awaits.
#    A captured record is GOOD (informational), not drift.
if [ -r /sys/fs/pstore ]; then
  _n="$(ls /sys/fs/pstore 2>/dev/null | wc -l)"
  if [ "${_n:-0}" = "0" ]; then
    _say pstore "OK: empty (no crash records)"
  else
    _say pstore "NOTE: ${_n} record(s) present -- a crash was captured (sudo cat /sys/fs/pstore/*)"
  fi
else
  _say pstore "n/a: /sys/fs/pstore not readable (run under root?)"
fi

exit $_drift
