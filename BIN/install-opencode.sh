#!/bin/bash
set -euo pipefail

PLUGINS_DIR="${PLUGINS_DIR:-$HOME/archive/ed3dai/ed3d-plugins/plugins}"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.config/opencode/skills}"
DRY_RUN="${DRY_RUN:-false}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SKILL_PATHS...]

Install opencode skills from ed3d-plugins to ~/.config/opencode/skills/

Arguments:
  SKILL_PATHS...    One or more skill paths in format: plugin-name/skills/skill-name
                    Can also be set via PLUGINS environment variable (comma-separated)

Environment:
  PLUGINS           Comma-separated list of skill paths (alternative to positional args)
  PLUGINS_DIR       Base plugins directory (default: ~/archive/ed3dai/ed3d-plugins/plugins)
  SKILLS_DIR        Target skills directory (default: ~/.config/opencode/skills)
  DRY_RUN           If "true", only print what would be done without making changes

Examples:
  # Install single skill via argument
  $(basename "$0") ed3d-research-agents/skills/investigating-a-codebase

  # Install multiple skills via PLUGINS env
  PLUGINS=ed3d-house-style/skills/coding-effectively,ed3d-basic-agents/skills/using-generic-agents $(basename "$0")

  # Install all skills from a plugin
  $(basename "$0") ed3d-house-style/skills/*
EOF
    exit "${1:-0}"
}

log() {
    echo "[install-opencode] $*"
}

log_dry() {
    echo "[DRY-RUN] $*"
}

install_skill() {
    local skill_path="$1"
    local src_dir="$PLUGINS_DIR/$skill_path"
    local skill_name
    skill_name=$(basename "$skill_path")
    local dest_link="$SKILLS_DIR/$skill_name"

    if [[ ! -d "$src_dir" ]]; then
        log "ERROR: Source directory not found: $src_dir"
        return 1
    fi

    if [[ ! -f "$src_dir/SKILL.md" ]]; then
        log "ERROR: No SKILL.md found in: $src_dir"
        return 1
    fi

    mkdir -p "$SKILLS_DIR"

    if [[ -L "$dest_link" ]]; then
        local current_target
        current_target=$(readlink -f "$dest_link")
        local src_real
        src_real=$(readlink -f "$src_dir")
        if [[ "$current_target" == "$src_real" ]]; then
            log "Already installed: $skill_name -> $src_dir"
            return 0
        else
            log "Replacing existing link: $skill_name (was -> $current_target)"
        fi
    elif [[ -e "$dest_link" ]]; then
        log "ERROR: Destination exists and is not a symlink: $dest_link"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "ln -s $src_dir $dest_link"
    else
        ln -sfv "$src_dir" "$dest_link"
    fi
}

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
    fi

    local skills=()

    if [[ -n "${PLUGINS:-}" ]]; then
        IFS=',' read -ra skills <<< "$PLUGINS"
    fi

    for arg in "$@"; do
        skills+=("$arg")
    done

    if [[ ${#skills[@]} -eq 0 ]]; then
        log "ERROR: No skills specified. Use PLUGINS env or pass skill paths as arguments."
        usage 1
    fi

    log "Installing ${#skills[@]} skill(s) to $SKILLS_DIR"
    log "Source directory: $PLUGINS_DIR"

    local failed=0
    for skill_path in "${skills[@]}"; do
        skill_path="${skill_path%/}"
        if ! install_skill "$skill_path"; then
            ((failed++))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log "Completed with $failed error(s)"
        exit 1
    fi

    log "Done!"
}

main "$@"
