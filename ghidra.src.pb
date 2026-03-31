---
- hosts: all
  vars:
    REPO: https://github.com/NationalSecurityAgency/ghidra
    PKGS:
      - default-jdk
      - libarchive-tools
    ENV_LIST:
      - opt
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
          bsdtar --strip-components=1 -xf "${zip}" -C "$OPT"
      - name: ghidraRun
        global: True
        content: |
          exec "$OPT/ghidraRun" "$@"
      - name: analyzeHeadless
        global: True
        content: |
          exec "$OPT/support/analyzeHeadless" "$@"
  tasks:
    - import_tasks: tasks/compfuzor.includes
