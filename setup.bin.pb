---
- hosts: all
  tasks:
    - name: setup
      action: setup
      register: setup_output
    - copy:
        content: "{{setup_output|to_nice_json}}"
        dest: ansible-setup.json
    - copy: 
        content: "{{vars}}"
        dest: ansible-vars.json
    #- copy:
    #    content: "{{hostvars}}
    #    dest: ansible-hostvars.json
    - copy:
        content: "{{lookup('file', '/proc/self/cmdline') | regex_replace('\u0000',' ') }}"
        dest: ansible-cmdline
    - debug:
        msg: "{{ ansible_play_name }}"
