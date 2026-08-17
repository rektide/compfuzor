# Add tangled.sh remote to jujutsu repo
addTngl() {
  jj git remote add tngl "tngl:jauntywk.bsky.social/${DIR:-$(basename "$(pwd)")}"
  jj bookmark track main --remote=tngl
}
