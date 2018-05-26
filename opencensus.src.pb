- hosts: all
  vars:
    TYPE: opencensus
    INSTANCE: git
    REPOS:
    - https://github.com/census-instrumentation/opencensus-go
    - https://github.com/census-instrumentation/opencensus-proto
    - https://github.com/census-instrumentation/opencensus-java
    - https://github.com/census-instrumentation/opencensus-python
    - https://github.com/census-instrumentation/opencensus-node
    - https://github.com/census-instrumentation/opencensus-erlang
    - https://github.com/census-instrumentation/opencensus-specs
    - https://github.com/census-instrumentation/opencensus-website
    - https://github.com/census-instrumentation/opencensus-cpp
    - https://github.com/census-instrumentation/opencensus-php
    - https://github.com/census-instrumentation/census-instrumentation.github.io
    - https://github.com/census-instrumentation/opencensus-ruby
    - https://github.com/census-instrumentation/opencensus-js-core
    - https://github.com/census-instrumentation/opencensus-csharp
    - https://github.com/census-instrumentation/opencensus-web
  tasks:
  - include: tasks/compfuzor.includes type=src
