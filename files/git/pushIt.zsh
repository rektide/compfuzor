# Push to multiple remotes (tngl, rektide, github, origin)
pushIt() {
  jj bookmark set $B -r @- --allow-backwards

  jj git remote list | awk '{print $1}' | grep -q "tngl" && jj git push -b $B --remote tngl &
  jj git remote list | awk '{print $1}' | grep -q "rektide" && jj git push -b $B --remote rektide &
  jj git remote list | awk '{print $1}' | grep -q "github" && jj git push -b $B --remote github &

  if ! (jj git remote list | awk '{print $1}' | grep -q "rektide\|github") || ! jj git remote list | grep "^origin" | grep -q "github\.com"; then
    jj git push -b $B &
  fi
}
