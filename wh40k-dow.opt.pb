---
# by way of https://steamcommunity.com/sharedfiles/filedetails/?id=1581447880
- hosts: all
  vars:
    TYPE: wh40k-dow
    INSTANCE: main
    ETC_FILES:
      - name: local-ini.yaml
        yaml:
          event_detail_level: 2
          fullres_teamcolour: 1
          force_watch_movies: 0
          fx_detail_level: 2
          modeldetail: 2
          parentalcontrol: 0
          #screenheight: 1800
          #screenwidth: 3200
          #screenwindowed: 1
          #screenrefresh: 90
    BINS:
      - name: install.sh
        basedir: False
        content: |
          # run from game directory
          [ ! -e ./Local.ini ] && echo "Missing Local.ini" >&2 && exit 1

          while IFS=':' read -r key value; do
              # Skip lines that start with # (comments)
              if [[ "$key" =~ ^[[:space:]]*# ]]; then
                  continue
              fi
              
              # Remove leading/trailing whitespace from key and value
              key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              
              # Skip empty lines or lines without proper key:value format
              if [ -z "$key" ] || [ -z "$value" ]; then
                  continue
              fi
              
              # Check if the key already exists in Local.ini
              if grep -q "^$key=" "Local.ini"; then
                  # Replace existing key=value line
                  sed -i "s/^$key=.*/$key=$value\r/" "Local.ini"
              else
                  # Add new key=value line using sed append
                  sed -i "\$a$key=$value\r" "Local.ini"
              fi
              dos2unix 
          done < $DIR/etc/local-ini.yaml
  tasks:
    - import_tasks: tasks/compfuzor.includes
