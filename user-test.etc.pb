---
- hosts: all
  vars:
    # Test-account factory: throwaway shell users for rehearsing user-scope
    # compfuzor installs (zim2/mise2 with USERMODE=True) without polluting
    # real accounts. Users land in a UID/GID band above the normal range
    # (login.defs UID_MAX/GID_MAX is 60000; default band 61000-61199), and
    # the operator gets passwordless sudo TO them (never from them):
    #
    #   ansible-playbook -i 'localhost,' -c local user-test.etc.pb -e USER_TEST_USERS=zimtest
    #   sudo -u zimtest -H zsh -lc 'id; echo $HOME'
    #   /etc/opt/user-test/bin/user-remove.sh zimtest   # manual teardown
    #
    # user-add/user-status run during the playbook via become (useradd,
    # /etc/sudoers.d writes); gate them with BINS_RUN_BYPASS=True like any
    # other subsystem. user-remove is manual-only.
    USER_TEST_BASE_UID: 61000
    USER_TEST_UID_SPAN: 200
    USER_TEST_SHELL: /usr/bin/zsh
    USER_TEST_OPERATOR: rektide
    # Space- or comma-separated names; empty means "factory idle".
    USER_TEST_USERS: ""
    BINS:
      - name: user-add.sh
        src: ../user-test/user-add.sh
        run: true
        become: true
        vars: [USER_TEST_BASE_UID, USER_TEST_UID_SPAN, USER_TEST_SHELL, USER_TEST_OPERATOR, USER_TEST_USERS]
      - name: user-status.sh
        src: ../user-test/user-status.sh
        run: true
        become: true
        vars: [USER_TEST_USERS]
      - name: user-remove.sh
        src: ../user-test/user-remove.sh
        vars: [USER_TEST_USERS]
  tasks:
    - import_tasks: tasks/compfuzor.includes
