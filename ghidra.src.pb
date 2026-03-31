---
- hosts: all
  vars:
    REPO: https://github.com/NationalSecurityAgency/ghidra
    PKGS:
      - default-jdk
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          ./gradlew -I gradle/support/fetchDependencies.gradle && ./gradlew assembleAll -x ip
          cd build/dist
          latest=$(ls -d ghidra_*/ 2>/dev/null | sort | tail -1)
          for d in ghidra_*/; do [ "$d" != "$latest" ] && rm -rf "$d"; done
          rm -f *.zip
      - name: ghidraRun
        global: True
        content: |
          exec "$(ls -d "$DIR/repo/build/dist/ghidra_*/" | head -1)ghidraRun" "$@"
      - name: analyzeHeadless
        global: True
        content: |
          exec "$(ls -d "$DIR/repo/build/dist/ghidra_*/" | head -1)support/analyzeHeadless" "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
