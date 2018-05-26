- hosts: all
  vars:
    TYPE: micronaut
    INSTANCE: git
    REPOS:
    - https://github.com/micronaut-projects/micronaut-core
    - https://github.com/micronaut-projects/micronaut-profiles
    - https://github.com/micronaut-projects/micronaut-examples
    - https://github.com/micronaut-projects/micronaut-guides
    - https://github.com/micronaut-projects/static-website
    - https://github.com/micronaut-projects/presentations
  tasks:
  - include: tasks/compfuzor.includes type=src
