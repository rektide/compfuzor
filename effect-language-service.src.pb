---
- hosts: all
  vars:
    REPO: https://github.com/Effect-TS/language-service.git
    NODEJS: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
      
    - name: Create merge-effect-lsp script
      copy:
        content: |
          #!/bin/bash
          set -e
          
          FRAGMENT='{
            "compilerOptions": {
              "plugins": [
                {
                  "name": "@effect/language-service"
                }
              ]
            }
          }'
          
          if [ ! -f tsconfig.json ]; then
            echo "{}" > tsconfig.json
          fi
          
          jq --argjson fragment "$FRAGMENT" '.
            | .compilerOptions //= {}
            | .compilerOptions.plugins //= []
            | if (.compilerOptions.plugins | map(select(.name == "@effect/language-service")) | length) == 0 then
                .compilerOptions.plugins += [{"name": "@effect/language-service"}]
              else
                .
              end
          ' tsconfig.json > tsconfig.json.tmp && mv tsconfig.json.tmp tsconfig.json
          
          echo "Effect language service plugin added to tsconfig.json"
        dest: "{{SRCS_DIR}}/merge-effect-lsp.sh"
        mode: '0755'
      vars:
        basedir: False
