---
- hosts: all
  vars:
    REPO: https://github.com/panproto/panproto-toolkit
    PLUGINS_DIR: "{{SRC}}"
    SKILLS_DIR: "$HOME/.config/opencode/skills"
    AGENTS_DIR: "$HOME/.config/opencode/agents"
    PLUGINS:
      - skills/breaking-change-ci
      - skills/build-migration
      - skills/build-protocol
      - skills/closed-sorts-and-case
      - skills/coercion-law-checks
      - skills/contributing
      - skills/convert-data
      - skills/cross-protocol
      - skills/define-schema
      - skills/dependent-optics
      - skills/expression-language
      - skills/field-transforms
      - skills/format-preserving
      - skills/full-ast-parsing
      - skills/getting-started
      - skills/implicit-arguments
      - skills/lens-dsl
      - skills/protolenses
      - skills/query-instances
      - skills/repl
      - skills/rewriting
      - skills/schema-vcs
      - skills/sdk-python
      - skills/sdk-rust
      - skills/sdk-typescript
      - skills/typeclasses
      - skills/use-lenses
      - ci-integrations/breaking-change-gate
      - ci-integrations/github-actions
      - ci-integrations/pre-commit-hooks
    AGENT_PLUGINS:
      - agents/compatibility-checker
      - agents/data-converter
      - agents/migration-advisor
      - agents/schema-reviewer
      - agents/vcs-assistant
    ENV_LIST:
      - plugins_dir
      - skills_dir
      - agents_dir
      - plugins
      - agent_plugins
    BINS:
      - name: install-opencode.sh
        basedir: False
        global: True
        content: |
          DRY_RUN="${DRY_RUN:-false}"

          usage() {
              cat <<EOF
          Usage: $(basename "$0") [OPTIONS] [SKILL_PATHS...]

          Install opencode skills and agents from panproto-toolkit.

          Arguments:
            SKILL_PATHS...    One or more skill paths (e.g. skills/define-schema, ci-integrations/github-actions)
                              Can also be set via PLUGINS environment variable (newline-separated)

          Environment:
            PLUGINS           Newline-separated list of skill paths (lines starting with # are skipped)
            AGENT_PLUGINS     Newline/comma/space separated list of agent paths
            PLUGINS_DIR       Base toolkit directory (default: ~/archive/panproto/panproto-toolkit)
            SKILLS_DIR        Target skills directory (default: ~/.config/opencode/skills)
            AGENTS_DIR        Target agents directory (default: ~/.config/opencode/agents)
            INSTALL_SKILLS    Set to "false" to skip skill installation
            INSTALL_AGENTS    Set to "false" to skip agent installation
            DRY_RUN           If "true", only print what would be done without making changes

          Examples:
            $(basename "$0") skills/define-schema skills/use-lenses
            PLUGINS=$(printf '%s\n' skills/build-protocol skills/cross-protocol) $(basename "$0")
          EOF
              exit "${1:-0}"
          }

          log() { echo "[install-opencode] $*"; }
          log_dry() { echo "[DRY-RUN] $*"; }

          parse_entries() {
              local raw="$1"
              local -n active_ref="$2"
              local -n commented_ref="$3"
              local line token in_comment

              while IFS= read -r line; do
                  line="${line#"${line%%[![:space:]]*}"}"
                  [[ -z "$line" ]] && continue

                  if [[ "$line" =~ ^# ]]; then
                      line="${line#\#}"
                      line="${line#"${line%%[![:space:]]*}"}"
                      [[ -z "$line" ]] && continue
                      in_comment=1
                  else
                      in_comment=0
                  fi

                  line="${line//,/ }"
                  for token in $line; do
                      [[ "$token" =~ ^# ]] && break
                      if [[ "$in_comment" -eq 1 ]]; then
                          commented_ref+=("$token")
                      else
                          active_ref+=("$token")
                      fi
                  done
              done <<< "$raw"
          }

          link_path() {
              local src_path="$1"
              local dest_path="$2"
              local label="$3"

              if [[ -L "$dest_path" ]]; then
                  local current_target
                  current_target=$(readlink -f "$dest_path")
                  local src_real
                  src_real=$(readlink -f "$src_path")
                  if [[ "$current_target" == "$src_real" ]]; then
                      log "Already installed: $label"
                      return 0
                  fi
                  log "Replacing: $label"
              elif [[ -e "$dest_path" ]]; then
                  log "ERROR: Destination exists (not symlink): $dest_path"
                  return 1
              fi

              if [[ "$DRY_RUN" == "true" ]]; then
                  log_dry "ln -s $src_path $dest_path"
              else
                  ln -sfv "$src_path" "$dest_path"
              fi
          }

          install_skill() {
              local skill_path="$1"
              local src_dir="$PLUGINS_DIR/$skill_path"
              local skill_name
              skill_name=$(basename "$skill_path")
              local dest_link="$SKILLS_DIR/$skill_name"

              [[ -d "$src_dir" ]] || { log "ERROR: Source not found: $src_dir"; return 1; }
              [[ -f "$src_dir/SKILL.md" ]] || { log "ERROR: No SKILL.md in: $src_dir"; return 1; }

              mkdir -p "$SKILLS_DIR"
              link_path "$src_dir" "$dest_link" "$skill_name"
          }

          install_agent() {
              local agent_path="$1"
              local src_dir="$PLUGINS_DIR/$agent_path"
              local agent_name
              agent_name=$(basename "$agent_path")
              local dest_link="$AGENTS_DIR/$agent_name"

              [[ -d "$src_dir" ]] || { log "ERROR: Source not found: $src_dir"; return 1; }
              [[ -f "$src_dir/SKILL.md" ]] || { log "ERROR: No SKILL.md in: $src_dir"; return 1; }

              mkdir -p "$AGENTS_DIR"
              link_path "$src_dir" "$dest_link" "$agent_name"
          }

          uninstall_skill() {
              local skill_path="$1"
              local skill_name
              skill_name=$(basename "$skill_path")
              local dest_link="$SKILLS_DIR/$skill_name"

              if [[ -L "$dest_link" ]]; then
                  if [[ "$DRY_RUN" == "true" ]]; then
                      log_dry "rm $dest_link"
                  else
                      rm -fv "$dest_link"
                      log "Removed skill: $skill_name"
                  fi
              fi
          }

          uninstall_agent() {
              local agent_path="$1"
              local agent_name
              agent_name=$(basename "$agent_path")
              local dest_link="$AGENTS_DIR/$agent_name"

              if [[ -L "$dest_link" ]]; then
                  if [[ "$DRY_RUN" == "true" ]]; then
                      log_dry "rm $dest_link"
                  else
                      rm -fv "$dest_link"
                      log "Removed agent: $agent_name"
                  fi
              fi
          }

          main() {
              [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] && usage

              local active_skills=()
              local commented_skills=()
              local active_agents=()
              local commented_agents=()

              [[ -n "${PLUGINS:-}" ]] && parse_entries "$PLUGINS" active_skills commented_skills
              active_skills+=("$@")

              [[ -n "${AGENT_PLUGINS:-}" ]] && parse_entries "$AGENT_PLUGINS" active_agents commented_agents

              [[ ${{'{#'}}active_skills[@]} -eq 0 && ${{'{#'}}active_agents[@]} -eq 0 && ${{'{#'}}commented_skills[@]} -eq 0 && ${{'{#'}}commented_agents[@]} -eq 0 ]] && { log "ERROR: No skills or agents specified"; usage 1; }

              local failed=0

              if [[ "${INSTALL_SKILLS:-true}" != "false" ]]; then
                  for skill_path in "${commented_skills[@]}"; do
                      skill_path="${skill_path%/}"
                      uninstall_skill "$skill_path" || ((failed++))
                  done

                  [[ ${{'{#'}}active_skills[@]} -gt 0 ]] && log "Installing ${{'{#'}}active_skills[@]} skill(s) to $SKILLS_DIR"
                  for skill_path in "${active_skills[@]}"; do
                      skill_path="${skill_path%/}"
                      install_skill "$skill_path" || ((failed++))
                  done
              fi

              if [[ "${INSTALL_AGENTS:-true}" != "false" ]]; then
                  for agent_path in "${commented_agents[@]}"; do
                      agent_path="${agent_path%/}"
                      uninstall_agent "$agent_path" || ((failed++))
                  done

                  [[ ${{'{#'}}active_agents[@]} -gt 0 ]] && log "Installing ${{'{#'}}active_agents[@]} agent(s) to $AGENTS_DIR"
                  for agent_path in "${active_agents[@]}"; do
                      agent_path="${agent_path%/}"
                      install_agent "$agent_path" || ((failed++))
                  done
              fi

              [[ $failed -gt 0 ]] && { log "Completed with $failed error(s)"; exit 1; }
              log "Done!"
          }

          main "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
