---
- hosts: all
  vars:
    TYPE: letta
    INSTANCE: git
    REPO: https://github.com/letta-ai/letta
    PKGS:
      - python3-venv
      - libpq-dev
      - python3-dev
    ENV:
      LETTA_ENVIRONMENT: DEV
      # needs pgvector
      LETTA_PG_URL: postgres://letta:letta@localhost/letta
      # defaults from https://docs.letta.com/guides/selfhosting/performance/
      LETTA_UVICORN_WORKERS: 1
      LETTA_UVICORN_RELOAD: False
      LETTA_UVICORN_TIMEOUT_KEEY_ALIVE: 5
      LETTA_PG_POOL_SIZE: 80
      LETTA_PG_MAX_OVERFLOW: 30
      LETTA_PG_POOL_TIMEOUT: 30
      LETTA_PG_POOL_RECYCLE: 1800
      # telemetry from https://docs.letta.com/guides/server/otel/
      #LETTA_OTEL_EXPORTER_OLTP_ENDPOINT: http://localhost:4317
      # clickhouse
      #CLICKHOUSE_ENDPOINT: localhost:9000
      #CLICKHOUSE_DATABASE: letta-telemery
      #CLICKHOUSE_USERNAME: letta
      #CLICKHOUSE_PASSWORD: letta
      # signoz
      #SIGNOZ_ENDPOINT: localhost:9000
      #SIGNOZ_INGESTION_KEY: password
    BINS:
      - name: build.sh
        content: |
          # from Dockerfile
          uv sync --frozen --no-dev --all-extras # python 3.11
  tasks:
    - import_tasks: tasks/compfuzor.includes
