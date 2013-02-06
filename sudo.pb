---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.vars
  tasks:
  - apt: state=${APT_INSTALL} pkg=sudo
    only_if: not ${APT_BYPASS}
  - user: name=$item groups=sudo append=true # BEWARE new users being created
    with_lines:
    - cat private/sudoers
