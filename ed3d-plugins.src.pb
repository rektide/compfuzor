---
- hosts: all
  vars:
    REPO: https://github.com/ed3dai/ed3d-plugins
    PLUGINS_DIR: "{{SRC}}/plugins"
    SKILLS_DIR: "$HOME/.config/opencode/skills"
    AGENTS_DIR: "$HOME/.config/opencode/agents"
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
      - agents_dir
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

          Install opencode skills and agents from ed3d-plugins.

          Arguments:
            SKILL_PATHS...    One or more skill paths in format: plugin-name/skills/skill-name
                              Can also be set via PLUGINS environment variable (newline-separated)

          Environment:
            PLUGINS           Newline-separated list of skill paths (lines starting with # are skipped)
            PLUGINS_DIR       Base plugins directory (default: ~/archive/ed3dai/ed3d-plugins/plugins)
            SKILLS_DIR        Target skills directory (default: ~/.config/opencode/skills)
            AGENTS_DIR        Target agents directory (default: ~/.config/opencode/agents)
            AGENT_PLUGINS     Optional plugin roots for agent install (newline/comma/space separated)
            INSTALL_SKILLS    Set to "false" to skip skill installation
            INSTALL_AGENTS    Set to "false" to skip agent installation
            DRY_RUN           If "true", only print what would be done without making changes

          Examples:
            $(basename "$0") ed3d-research-agents/skills/investigating-a-codebase
            PLUGINS=$(printf '%s\n' ed3d-house-style/skills/coding-effectively ed3d-basic-agents/skills/using-generic-agents) $(basename "$0")
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

          install_plugin_agents() {
              local plugin_root="$1"
              local src_agents_dir="$PLUGINS_DIR/$plugin_root/agents"

              [[ -d "$src_agents_dir" ]] || return 0
              mkdir -p "$AGENTS_DIR"

              local agent_src
              local installed_any=0
              for agent_src in "$src_agents_dir"/*.md; do
                  [[ -e "$agent_src" ]] || continue
                  installed_any=1

                  local agent_file
                  agent_file=$(basename "$agent_src")
                  local plugin_label
                  plugin_label="${plugin_root//\//-}"
                  local dest_link="$AGENTS_DIR/$plugin_label--$agent_file"

                  link_path "$agent_src" "$dest_link" "$plugin_label/$agent_file" || return 1
              done

              [[ "$installed_any" -eq 1 ]] && log "Installed agents for plugin: $plugin_root"
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

          uninstall_plugin_agents() {
              local plugin_root="$1"
              local src_agents_dir="$PLUGINS_DIR/$plugin_root/agents"

              [[ -d "$src_agents_dir" ]] || return 0

              local agent_src
              for agent_src in "$src_agents_dir"/*.md; do
                  [[ -e "$agent_src" ]] || continue

                  local agent_file
                  agent_file=$(basename "$agent_src")
                  local plugin_label
                  plugin_label="${plugin_root//\//-}"
                  local dest_link="$AGENTS_DIR/$plugin_label--$agent_file"

                  if [[ -L "$dest_link" ]]; then
                      if [[ "$DRY_RUN" == "true" ]]; then
                          log_dry "rm $dest_link"
                      else
                          rm -fv "$dest_link"
                          log "Removed agent: $plugin_label/$agent_file"
                      fi
                  fi
              done
          }

          main() {
              [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]] && usage

              local active_skills=()
              local commented_skills=()
              local active_agent_plugins=()
              local commented_agent_plugins=()

              [[ -n "${PLUGINS:-}" ]] && parse_entries "$PLUGINS" active_skills commented_skills
              active_skills+=("$@")

              [[ -n "${AGENT_PLUGINS:-}" ]] && parse_entries "$AGENT_PLUGINS" active_agent_plugins commented_agent_plugins

              [[ ${{'{#'}}active_skills[@]} -eq 0 && ${{'{#'}}active_agent_plugins[@]} -eq 0 && ${{'{#'}}commented_skills[@]} -eq 0 && ${{'{#'}}commented_agent_plugins[@]} -eq 0 ]] && { log "ERROR: No skills or agent plugins specified"; usage 1; }

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
                  declare -A active_plugin_roots=()
                  declare -A commented_plugin_roots=()

                  local skill_path plugin_root
                  for skill_path in "${active_skills[@]}"; do
                      [[ "$skill_path" == */skills/* ]] || continue
                      plugin_root="${skill_path%%/skills/*}"
                      [[ -n "$plugin_root" ]] && active_plugin_roots["$plugin_root"]=1
                  done

                  for skill_path in "${commented_skills[@]}"; do
                      [[ "$skill_path" == */skills/* ]] || continue
                      plugin_root="${skill_path%%/skills/*}"
                      [[ -n "$plugin_root" ]] && commented_plugin_roots["$plugin_root"]=1
                  done

                  for plugin_root in "${active_agent_plugins[@]}"; do
                      plugin_root="${plugin_root%/}"
                      [[ -n "$plugin_root" ]] && active_plugin_roots["$plugin_root"]=1
                  done

                  for plugin_root in "${commented_agent_plugins[@]}"; do
                      plugin_root="${plugin_root%/}"
                      [[ -n "$plugin_root" ]] && commented_plugin_roots["$plugin_root"]=1
                  done

                  for plugin_root in "${!commented_plugin_roots[@]}"; do
                      uninstall_plugin_agents "$plugin_root" || ((failed++))
                  done

                  if [[ ${{'{#'}}active_plugin_roots[@]} -gt 0 ]]; then
                      log "Installing agents from ${{'{#'}}active_plugin_roots[@]} plugin(s) to $AGENTS_DIR"
                      for plugin_root in "${!active_plugin_roots[@]}"; do
                          install_plugin_agents "$plugin_root" || ((failed++))
                      done
                  fi
              fi

              [[ $failed -gt 0 ]] && { log "Completed with $failed error(s)"; exit 1; }
              log "Done!"
          }

          main "$@"
      - name: frontmatter-simplify
        basedir: False
        global: True
        content: |
          set -euo pipefail
          DRY_RUN="${DRY_RUN:-false}"
          SHOW_DIFF="${SHOW_DIFF:-false}"

          color_to_hex() {
              local color_name="$1"
              local rgb
              rgb=$(showrgb | awk -v name="$color_name" '
                  {
                      cname = ""
                      for (i = 4; i <= NF; i++) {
                          cname = cname (i > 4 ? " " : "") $i
                      }
                      if (tolower(cname) == tolower(name)) {
                          printf "%02X%02X%02X", $1, $2, $3
                          exit
                      }
                  }
              ')
              if [[ -n "$rgb" ]]; then
                  echo "#$rgb"
                  return 0
              fi
              return 1
          }

          convert_file() {
              local file="$1"
              local in_frontmatter=false
              local changed=false
              local temp_file
              temp_file=$(mktemp)

              while IFS= read -r line || [[ -n "$line" ]]; do
                  if [[ "$line" == "---" ]]; then
                      if [[ "$in_frontmatter" == "false" ]]; then
                          in_frontmatter=true
                      else
                          in_frontmatter=false
                      fi
                      echo "$line" >> "$temp_file"
                      continue
                  fi

                  if [[ "$in_frontmatter" == "true" ]] && [[ "$line" =~ ^color:[[:space:]]+([^#[:space:]].*) ]]; then
                      color_name="${BASH_REMATCH[1]}"
                      hex=$(color_to_hex "$color_name")
                      if [[ -n "$hex" ]]; then
                          echo "color: \"$hex\"" >> "$temp_file"
                          echo "  $file: '$color_name' -> '$hex'" >&2
                          if [[ "$SHOW_DIFF" == "true" ]]; then
                              echo "    - $line" >&2
                              echo "    + color: \"$hex\"" >&2
                          fi
                          changed=true
                      else
                          echo "$line" >> "$temp_file"
                          echo "  $file: unknown color '$color_name'" >&2
                      fi
                  elif [[ "$in_frontmatter" == "true" ]] && [[ "$line" =~ ^(tools|model): ]]; then
                      echo "  $file: removed '${BASH_REMATCH[1]}' line" >&2
                      if [[ "$SHOW_DIFF" == "true" ]]; then
                          echo "    - $line" >&2
                      fi
                      changed=true
                  else
                      echo "$line" >> "$temp_file"
                  fi
              done < "$file"

              if [[ "$changed" == "true" ]]; then
                  if [[ "$DRY_RUN" == "true" ]]; then
                      echo "  $file: [DRY-RUN] would write changes" >&2
                      rm "$temp_file"
                  else
                      mv "$temp_file" "$file"
                  fi
              else
                  rm "$temp_file"
              fi
          }

          if [[ $# -eq 0 ]]; then
              echo "Usage: $(basename "$0") [OPTIONS] <file.md> [file2.md ...]" >&2
              echo "       $(basename "$0") --dir <directory>" >&2
              echo "" >&2
              echo "Options:" >&2
              echo "  --dry-run          Show what would change without modifying files" >&2
              echo "  --diff             Implies --dry-run; also shows the exact lines removed/changed" >&2
              echo "  --dir              Process all .md files under a directory" >&2
              echo "  --no-follow        Don't follow symlinks (follows by default)" >&2
              echo "  --pattern <regex>  Pattern to match for removal (default: '^color:|^model:|^tools:')" >&2
              echo "  --glob <glob>      File glob to search (default: '*.md')" >&2
              echo "" >&2
              echo "Environment:" >&2
              echo "  DRY_RUN            Set to 'true' to enable dry-run mode" >&2
              exit 1
          fi

          args=()
          dir_mode=false
          FOLLOW="-L"
          RG_PATTERN='^color:|^model:|^tools:'
          RG_GLOB='*.md'
          for arg in "$@"; do
              case "$arg" in
                  --dry-run) DRY_RUN=true ;;
                  --diff) DRY_RUN=true; SHOW_DIFF=true ;;
                  --dir) dir_mode=true ;;
                  --no-follow) FOLLOW="" ;;
                  --pattern)
                      shift; RG_PATTERN="$1"
                      ;;
                  --glob)
                      shift; RG_GLOB="$1"
                      ;;
                  *) args+=("$arg") ;;
              esac
          done

          if [[ "$dir_mode" == "true" ]]; then
              dir="${args[0]:-.}"
              rg -S $FOLLOW -l "$RG_PATTERN" -g "$RG_GLOB" "$dir" | while read -r file; do
                  convert_file "$file"
              done
          else
              for file in "${args[@]}"; do
                  convert_file "$file"
              done
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
