---
- hosts: all
  vars:
    TYPE: lemonade
    INSTANCE: git
    REPO: https://github.com/lemonade-sdk/lemonade
    ENV: True
    BINS:
      - name: build.sh
        content: |
          # https://github.com/lemonade-sdk/lemonade/blob/main/src/cpp/README.md#build-steps
          echo starting lemonade server build
          cd src/cpp
          mkdir -p build
          cd build
          cmake ..
          cmake --build . --config Release -j

          # https://github.com/lemonade-sdk/lemonade/blob/main/src/app/README.md
          echo starting lemonade app build
          cd $DIR/src/app
          pnpm install
          #pnpm run dev
          pnpm run build

  tasks:
    - import_tasks: tasks/compfuzor.includes
