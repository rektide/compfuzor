# user-test: report test users, their homes, and operator sudo grants.

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
  echo "== $name =="
  if ! ent=$(getent passwd "$name"); then
    echo "user: absent"
  else
    echo "$ent"
    home=$(getent passwd "$name" | cut -d: -f6)
    if [ -d "$home" ]; then
      echo "home: $home ($(stat -c '%U:%G %a' "$home"))"
    else
      echo "home: $home (missing)"
    fi
  fi
  sudoers=/etc/sudoers.d/61-user-test-$name
  if [ -f "$sudoers" ]; then
    echo "sudoers: $(cat "$sudoers")"
  else
    echo "sudoers: none"
  fi
done
