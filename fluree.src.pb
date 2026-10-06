---
# Fluree DB -- temporal graph DB (RDF/SPARQL/JSON-LD/openCypher/GraphQL).
# Rust workspace; the shipped artifact is the all-in-one `fluree` CLI with
# embedded HTTP server (`fluree server run`).
- hosts: all
  vars:
    REPO: https://github.com/fluree/db
    RUST: True
    RUST_PKG: fluree-db-cli # shipped CLI crate, not all 56 workspace members
    TOOL_VERSIONS: # align mise pin with the repo's rust-toolchain.toml
      rust: "1.97.0"
  tasks:
    - import_tasks: tasks/compfuzor.includes
