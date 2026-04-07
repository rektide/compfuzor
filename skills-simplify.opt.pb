---
- hosts: all
  vars:
    BINS:
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
              rgb=$(showrgb | awk --assign name="$color_name" '
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

              while IFS= read --r line || [[ -n "$line" ]]; do
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
                      rm --force "$temp_file"
                  else
                      mv "$temp_file" "$file"
                  fi
              else
                  rm --force "$temp_file"
              fi
          }

          if [[ $# -eq 0 ]]; then
              echo "Usage: $(basename "$0") [OPTIONS] <file.md> [file2.md ...]" >&2
              echo "       $(basename "$0") --dir <directory>" >&2
              echo "" >&2
              echo "Options:" >&2
              echo "  --dry-run          Show what would change without modifying files" >&2
              echo "  --diff             Implies --dry-run; also shows the exact lines removed/changed" >&2
              echo "  --dir              Process all matching files under a directory" >&2
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
          FOLLOW="--follow"
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
              rg --smart-case $FOLLOW --files-with-matches --glob "$RG_GLOB" --regexp "$RG_PATTERN" "$dir" | while read --r file; do
                  convert_file "$file"
              done
          else
              for file in "${args[@]}"; do
                  convert_file "$file"
              done
          fi
  tasks:
    - import_tasks: tasks/compfuzor.includes
