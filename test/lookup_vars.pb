---
- hosts: localhost
  gather_facts: false
  vars:
    FOO: foo-value
    BAR:
      nested: true
    VAR_NAMES:
      - FOO
      - BAR
      - MISSING
  tasks:
    - name: Resolve multiple variables into list and dictionary
      ansible.builtin.set_fact:
        RESOLVED_LIST: "{{ lookup('vars_list', VAR_NAMES, default='__missing__') }}"
        RESOLVED_DICT: "{{ lookup('vars_dict', VAR_NAMES, default='__missing__') }}"

    - name: Show vars_list output
      ansible.builtin.debug:
        var: RESOLVED_LIST

    - name: Show vars_dict output
      ansible.builtin.debug:
        var: RESOLVED_DICT

    - name: Verify lookups resolve values and defaults
      ansible.builtin.assert:
        that:
          - RESOLVED_LIST[0] == 'foo-value'
          - RESOLVED_LIST[1].nested
          - RESOLVED_LIST[2] == '__missing__'
          - RESOLVED_DICT.FOO == 'foo-value'
          - RESOLVED_DICT.BAR.nested
          - RESOLVED_DICT.MISSING == '__missing__'
