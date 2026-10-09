---
- hosts: all
  vars:
    REPO: https://github.com/jj-vcs/jj
    RUST: True
    ETC_FILES:
      - name: watchman.toml
        content: |
          # jujutsu
          #[fsmonitor]
          #backend = "watchman"
          #watchman.register-snapshot-trigger = true
      - name: snapshot.toml
        content: |
          [snapshot]
          # 2026-10-10: silent auto-recovery snapshotted near-empty quarantined
          # workspace dirs as mass deletions across ~55 workspaces (jj 0.45.1).
          # Stale workspaces must ERROR loudly instead; see the incident report
          # at /home/rektide/tmp-opencode/update-stale-report.glm53max.md.
          auto-update-stale = false
    BINS:
      - name: install-config.sh
        content: |
          CONFD_DIR="$HOME/.config/jj/conf.d"
          mkdir -p "$CONFD_DIR"

          for config_file in "$(pwd)"/etc/*.toml; do
            ln -sfv "$config_file" "$CONFD_DIR/"
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
