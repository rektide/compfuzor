---
- hosts: all
  vars:
    REPO: https://github.com/ed3dai/ed3d-plugins
    PLUGINS_DIR: "{{SRC}}/plugins"
    SKILLS_DIR: "$HOME/.config/opencode/skills"
    PLUGINS:
      - ed3d-basic-agents/skills/doing-a-simple-two-stage-fanout
      - ed3d-basic-agents/skills/using-generic-agents
      - ed3d-extending-claude/skills/creating-a-plugin
      - ed3d-extending-claude/skills/creating-an-agent
      - ed3d-extending-claude/skills/maintaining-a-marketplace
      - ed3d-extending-claude/skills/maintaining-project-context
      - ed3d-extending-claude/skills/prompt-security-hardening
      - ed3d-extending-claude/skills/testing-skills-with-subagents
      - ed3d-extending-claude/skills/writing-claude-directives
      - ed3d-extending-claude/skills/writing-claude-md-files
      - ed3d-extending-claude/skills/writing-skills
      - ed3d-house-style/skills/coding-effectively
      - ed3d-house-style/skills/defense-in-depth
      - ed3d-house-style/skills/howto-code-in-typescript
      - ed3d-house-style/skills/howto-develop-with-postgres
      - ed3d-house-style/skills/howto-functional-vs-imperative
      - ed3d-house-style/skills/programming-in-react
      - ed3d-house-style/skills/property-based-testing
      - ed3d-house-style/skills/writing-for-a-technical-audience
      - ed3d-house-style/skills/writing-good-tests
      - ed3d-plan-and-execute/skills/asking-clarifying-questions
      - ed3d-plan-and-execute/skills/brainstorming
      - ed3d-plan-and-execute/skills/executing-an-implementation-plan
      - ed3d-plan-and-execute/skills/finishing-a-development-branch
      - ed3d-plan-and-execute/skills/requesting-code-review
      - ed3d-plan-and-execute/skills/starting-a-design-plan
      - ed3d-plan-and-execute/skills/starting-an-implementation-plan
      - ed3d-plan-and-execute/skills/systematic-debugging
      - ed3d-plan-and-execute/skills/test-driven-development
      - ed3d-plan-and-execute/skills/using-git-worktrees
      - ed3d-plan-and-execute/skills/using-plan-and-execute
      - ed3d-plan-and-execute/skills/verification-before-completion
      - ed3d-plan-and-execute/skills/writing-design-plans
      - ed3d-plan-and-execute/skills/writing-implementation-plans
      - ed3d-playwright/skills/playwright-debugging
      - ed3d-playwright/skills/playwright-patterns
      - ed3d-research-agents/skills/investigating-a-codebase
      - ed3d-research-agents/skills/researching-on-the-internet
      - ed3d-session-reflection/skills/export-session-as-markdown
      - ed3d-session-reflection/skills/review-recent-sessions
      - ed3d-session-reflection/skills/review-session
    ENV_LIST:
      - plugins_dir
      - skills_dir
      - plugins
    BINS:
      - name: install-opencode.sh
        basedir: False
        global: True
        content: |
          DRY_RUN="${DRY_RUN:-false}"

          usage() {
              cat <<EOF
          Usage: $(basename "$0") [OPTIONS] [SKILL_PATHS...]

          Install opencode skills from ed3d-plugins to ~/.config/opencode/skills/

          Arguments:
            SKILL_PATHS...    One or more skill paths in format: plugin-name/skills/skill-name
                              Can also be set via PLUGINS environment variable (newline-separated)

          Environment:
            PLUGINS           Newline-separated list of skill paths (alternative to positional args)
            PLUGINS_DIR       Base plugins directory (default: ~/archive/ed3dai/ed3d-plugins/plugins)
            SKILLS_DIR        Target skills directory (default: ~/.config/opencode/skills)
            DRY_RUN           If "true", only print what would be done without making changes

          Examples:
            $(basename "$0") ed3d-research-agents/skills/investigating-a-codebase
            PLUGINS=$(printf '%s\n' ed3d-house-style/skills/coding-effectively ed3d-basic-agents/skills/using-generic-agents) $(basename "$0")
          EOF
              exit "${1:-0}"
          }

          log() { echo "[install-opencode] $*"; }
          log_dry() { echo "[DRY-RUN] $*"; }

          install_skill() {
              local skill_path="$1"
              local src_dir="$PLUGINS_DIR/$skill_path"
              local skill_name
              skill_name=$(basename "$skill_path")
              local dest_link="$SKILLS_DIR/$skill_name"

              [[ -d "$src_dir" ]] || { log "ERROR: Source not found: $src_dir"; return 1; }
              [[ -f "$src_dir/SKILL.md" ]] || { log "ERROR: No SKILL.md in: $src_dir"; return 1; }

              mkdir -p "$SKILLS_DIR"

              if [[ -L "$dest_link" ]]; then
                  local current_target
                  current_target=$(readlink -f "$dest_link")
                  local src_real
                  src_real=$(readlink -f "$src_dir")
                  if [[ "$current_target" == "$src_real" ]]; then
                      log "Already installed: $skill_name"
                      return 0
                  fi
                  log "Replacing: $skill_name"
              elif [[ -e "$dest_link" ]]; then
                  log "ERROR: Destination exists (not symlink): $dest_link"
                  return 1
              fi

              if [[ "$DRY_RUN" == "true" ]]; then
                  log_dry "ln -s $src_dir $dest_link"
              else
                  ln -sfv "$src_dir" "$dest_link"
              fi
          }

          main() {
              [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] && usage

              local skills=()
              [[ -n "${PLUGINS:-}" ]] && readarray -t skills <<< "$PLUGINS"
              skills+=("$@")

              [[ ${{'{#'}}skills[@]} -eq 0 ]] && { log "ERROR: No skills specified"; usage 1; }

              log "Installing ${{'{#'}}skills[@]} skill(s) to $SKILLS_DIR"

              local failed=0
              for skill_path in "${skills[@]}"; do
                  skill_path="${skill_path%/}"
                  install_skill "$skill_path" || ((failed++))
              done

              [[ $failed -gt 0 ]] && { log "Completed with $failed error(s)"; exit 1; }
              log "Done!"
          }

          main "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
