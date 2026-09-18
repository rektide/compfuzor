# user-test: create throwaway shell users in a high UID/GID band (default
# 61000-61199, above login.defs UID_MAX/GID_MAX=60000) with a matching
# per-user group, plus a passwordless operator->user sudo grant. Idempotent:
# existing users are left untouched, grants refresh to the current operator.

set -euo pipefail

users=("$@")
if [ ${#users[@]} -eq 0 ]; then
  read -r -a users <<<"${USER_TEST_USERS//,/ }"
fi
if [ ${#users[@]} -eq 0 ] || [ -z "${users[0]:-}" ]; then
  echo "user-test: no users requested (args or USER_TEST_USERS); nothing to do"
  exit 0
fi

base=${USER_TEST_BASE_UID:-61000}
span=${USER_TEST_UID_SPAN:-200}
shell=${USER_TEST_SHELL:-/usr/bin/zsh}
operator=${USER_TEST_OPERATOR:-${SUDO_USER:-rektide}}

for name in "${users[@]}"; do
  # Stable per-name uid inside the band; walk forward on collisions.
  uid=$(( base + ($(printf '%s' "$name" | cksum | cut -d' ' -f1) % span) ))
  while getent passwd "$uid" >/dev/null 2>&1 || getent group "$uid" >/dev/null 2>&1; do
    uid=$(( uid + 1 ))
  done

  if getent passwd "$name" >/dev/null; then
    echo "user-test: $name exists ($(id "$name"))"
  else
    getent group "$name" >/dev/null || groupadd -g "$uid" "$name"
    useradd -m -u "$uid" -g "$name" -s "$shell" "$name"
    echo "user-test: created $name (uid/gid $uid, shell $shell)"
  fi

  # sudoers.d names must not contain '.' or sudo ignores them.
  sudoers=/etc/sudoers.d/61-user-test-$name
  entry="$operator ALL=($name) NOPASSWD: ALL"
  if [ -f "$sudoers" ] && [ "$(cat "$sudoers")" = "$entry" ]; then
    echo "user-test: sudo grant $operator -> $name already current"
  else
    printf '%s\n' "$entry" >"$sudoers"
    chmod 0440 "$sudoers"
    visudo -cf "$sudoers" >/dev/null
    echo "user-test: granted $operator passwordless sudo to $name"
  fi
done
