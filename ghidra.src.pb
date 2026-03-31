---
- hosts: all
  vars:
    REPO: https://github.com/NationalSecurityAgency/ghidra
    PKGS:
      - default-jdk
      - libarchive-tools
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          ./gradlew -I gradle/support/fetchDependencies.gradle && ./gradlew buildGhidra -x ip
      - name: install.sh
        basedir: repo
        content: |
          cd build/dist
          zip=$(ls ghidra_*_PUBLIC_*.zip | head -1)
          bsdtar --strip-components=1 -xf "${zip}" -C "$DIR"
      - name: ghidraRun
        global: True
        content: |
          exec "$DIR/ghidraRun" "$@"
      - name: analyzeHeadless
        global: True
        content: |
          exec "$DIR/support/analyzeHeadless" "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
