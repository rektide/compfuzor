# Get current git branch name
git_branch() {
  ref=$(git symbolic-ref HEAD 2>/dev/null | cut -d'/' -f3)
  echo $ref
}
