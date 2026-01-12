---
- hosts: all
  vars:
    REPO: http://github.com/Dicklesworthstone/coding_agent_session_search/
    RUST: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
