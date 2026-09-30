---
- hosts: all
  vars:
    TYPE: cassandra
    INSTANCE: main
    # deb822 lane. DEAD UPSTREAM (apache's 21x suite is EOL; kept for
    # archaeology) -- do not deploy.
    APT:
      URIs: http://www.apache.org/dist/cassandra/debian
      Suites: 21x
      Components: [main]
  tasks:
  - import_tasks: tasks/compfuzor.includes
    vars:
      type: etc
