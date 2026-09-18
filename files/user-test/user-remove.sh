# user-test: remove test users (home + mail spool) and their sudo grants.
# Manual-only counterpart to user-add.sh: nothing invokes this automatically.

set -euo pipefail

users=("$@")
if [ ${#users[@]} -eq 0 ]; then
  read -r -a users <<<"${USER_TEST_USERS//,/ }"
fi
if [ ${#users[@]} -eq 0 ] || [ -z "${users[0]:-}" ]; then
  echo "user-test: no users requested (args or USER_TEST_USERS); nothing to do"
  exit 0
fi

for name in "${users[@]}"; do
  if getent passwd "$name" >/dev/null; then
    userdel -r "$name"
    groupdel "$name" 2>/dev/null || true
    echo "user-test: removed user $name"
  else
    echo "user-test: user $name absent"
    groupdel "$name" 2>/dev/null && echo "user-test: removed leftover group $name" || true
  fi
  sudoers=/etc/sudoers.d/61-user-test-$name
  if [ -f "$sudoers" ]; then
    rm -f "$sudoers"
    echo "user-test: removed $sudoers"
  fi
done
