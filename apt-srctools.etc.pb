---
# apt-srctools -- standalone apt sources.list manipulation tools.
#
# Six zero-dependency TypeScript bins (node --strip-types, parseArgs), all
# sharing one canonical JSON source model (apt-src-model.ts). JSON is the
# standard intermediate: classic <-> json and deb822 <-> json, so any format
# pair composes through it. The scheme tool maintains single URI rows via
# block-in-file where that is possible -- see design/apt-srctools/ for the
# fidelity map and the BIF wishlist.
#
# Deployed names keep the .ts suffix: node type-stripping is extension-gated,
# and the repo convention is to run .ts directly (script/apt-tunnel-mirrors.ts
# is the precedent).
- hosts: all
  vars:
    TYPE: apt-srctools
    BINS:
      # Shared model + classic/deb822 parse/emit. Library, not a command.
      - name: apt-src-model.ts
        raw: True
        mode: "0644"
      # classic (one-line .list) <-> JSON
      - name: apt-src-classic2json.ts
        raw: True
        global: True
      - name: apt-src-json2classic.ts
        raw: True
        global: True
      # deb822 (.sources) <-> JSON
      - name: apt-src-deb8222json.ts
        raw: True
        global: True
      - name: apt-src-json2deb822.ts
        raw: True
        global: True
      # Run every source file in a directory through the converters, moving
      # the dir to a specified format (classic|deb822).
      - name: apt-src-convert-dir.ts
        raw: True
        global: True
      # Toggle http <-> https on source URIs, maintaining just the URI row,
      # via block-in-file managed blocks where feasible.
      - name: apt-src-scheme.ts
        raw: True
        global: True
      # FUTURE (do not build yet -- strong-comment spec lands here after the
      # rest of this playbook settles): apt-src-pin-priority.ts -- rewrite
      # apt pin priorities for repos matching a distribution filter, e.g.
      # forky=X sid=Y experimental=Z. Starts hardcoded-narrow, generalizes
      # into --filter/--set later.
    README: |
      # apt-srctools

      apt sources.list manipulation tools. All share one JSON source model;
      conversions compose through it (classic <-> json, deb822 <-> json).

      - `apt-src-classic2json.ts` / `apt-src-json2classic.ts` -- one-line
        `.list` format <-> JSON (stdin/stdout, or --file/--out).
      - `apt-src-deb8222json.ts` / `apt-src-json2deb822.ts` -- deb822
        `.sources` stanzas <-> JSON.
      - `apt-src-convert-dir.ts [--to classic|deb822] [--dry-run] [DIR]` --
        detect each source file's format in a dir (default
        /etc/apt/sources.list.d) and move it to the target format.
      - `apt-src-scheme.ts --to https|http [FILE...]` -- flip the URI scheme
        on sources, maintaining just the URI row per entry via block-in-file
        managed blocks where possible.

      See design/apt-srctools/ for the JSON schema, the roundtrip fidelity
      map (what is bijective through JSON, what normalizes or is lossy), and
      the block-in-file wishlist.
  tasks:
    - import_tasks: tasks/compfuzor.includes
