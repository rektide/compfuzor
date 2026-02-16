---
- hosts: all
  vars:
    INSTANCE: swapfile
    SWAP_PATH: "/{{ INSTANCE | regex_replace('^swap-', '') }}"
    #SIZE: "{{SIZE|default('24G')}}"
    SIZE: 32
    SWAP_FILE: "{{INSTANCE|default(NAME|default(TYPE))|regex_replace('^swap-','')}}"
    SWAP_PATH: "/{{SWAP_FILE}}{{SWAP_EXT}}"
    SWAP_EXT: ""
    ENV:
      - SIZE
      - SWAP_PATH
    ETC_FILES:
      - name: swapfile.fstab
        content: |
          ${SWAP_PATH} none swap defaults 0 0
    BINS:
      - name: build.sh
        basedir: False
        content: |
          #!/bin/bash
          set -e
          
          SIZE="${SIZE:-{{ SIZE | default('24G') }}}"
          SWAP_PATH="/$(echo "$NAME" | sed 's/^swap-//')"
          
          if [ ! -f "$SWAP_PATH" ]; then
            echo "Creating swap file at $SWAP_PATH with size $SIZE"
            sudo truncate -s 0 "$SWAP_PATH"
            sudo chmod 600 "$SWAP_PATH"
            sudo chattr +C "$SWAP_PATH" 2>/dev/null || true
            sudo fallocate -l "$SIZE" "$SWAP_PATH" 2>/dev/null || sudo dd if=/dev/zero of="$SWAP_PATH" bs=1M count=$((${SIZE%G} * 1024))
            sudo chmod 600 "$SWAP_PATH"
            sudo mkswap "$SWAP_PATH" -L $NAME
          fi
          
          echo "Swap file $SWAP_PATH ready"
      - name: build-fstab.sh
        basedir: False
        content: |
          #!/bin/bash
          set -e
          
          # Run fstab generator to create .swap/.mount units from /etc/fstab
          sudo /usr/lib/systemd/system-generators/systemd-fstab-generator \
            /run/systemd/generator \
            /run/systemd/generator.early \
            /run/systemd/generator.late
      - name: install.sh
        basedir: False
        content: |
          #!/bin/bash
          set -e
          
          NAME="${NAME:-{{ INSTANCE }}}"
          export SWAP_PATH="/$(echo "$NAME" | sed 's/^swap-//')"
          
          # Build the swap file if needed
          {{ DIR }}/bin/build.sh
          
          # Add to /etc/fstab using block-in-file (pass SWAP_PATH through sudo)
          cat {{ DIR }}/etc/swapfile.fstab | sudo SWAP_PATH="$SWAP_PATH" block-in-file -n "$NAME" -o /etc/fstab --envsubst
          
          # Reload fstab generator to create mount units
          sudo systemctl daemon-reload
          
          # Enable the swap
          sudo swapon -a
          
          echo "Swap $NAME configured and enabled"
  tasks:
    - import_tasks: tasks/compfuzor.includes
