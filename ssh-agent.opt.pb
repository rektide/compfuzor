---
- hosts: all
  vars:
    TYPE: ssh-agent
    INSTANCE: main
    # Overhauled 2026-10-06 (was .srv.pb): this playbook no longer hosts its
    # own agent -- it ran `ssh-agent -D -a %t/ssh-agent.sock` as a user unit,
    # a rendezvous nothing else consumed. The distro now ships
    # ssh-agent.socket + ssh-agent.service (socket-activated at
    # %t/openssh_agent), and gcr-ssh-agent.socket (%t/gcr/ssh) serves the
    # keyring-integrated agent. The job here is consumption policy: which
    # channel owns SSH_AUTH_SOCK for shells, publishing a guarded selection
    # block into shell startup files, and neutralizing losing channels.
    #
    # Channel policy:
    #   gcr      gcr-ssh-agent wins; distro ssh-agent units are
    #            disabled+masked. Both sockets run `ExecStartPost systemctl
    #            --user set-environment SSH_AUTH_SOCK=...` so whichever
    #            socket starts later owns the user-manager environment --
    #            masking makes gcr deterministic there. The openssh agent
    #            held zero identities from Aug 10 onward: it never pulled
    #            weight. gcr is the gmellon story: keyring-stored passphrases
    #            make gcr-ssh-agent usable headless once the keyring is
    #            unlocked (Linger keeps %t/gcr/ssh up from boot).
    #   openssh  distro ssh-agent.socket rendezvous (%t/openssh_agent) is
    #            unmasked+enabled and preferred -- for hosts without
    #            gcr/keyring. Identities then need ssh-add or
    #            AddKeysToAgent; the distro unit sets SSH_ASKPASS_REQUIRE=force.
    ssh_agent_channel: gcr
    # Runtime-relative rendezvous paths, expanded by the loading shell (NOT
    # systemd EnvironmentFile literals -- systemd does no expansion; see
    # mise2's mise_npm_package_manager note). An inherited SSH_AUTH_SOCK that
    # still resolves to a unix socket is never clobbered: `ssh -A` agent
    # forwarding and session-provided agents always win. Only unset or stale
    # values fall through to candidate discovery.
    ssh_agent_socket_base: '${XDG_RUNTIME_DIR:-/run/user/$(id -u)}'
    ssh_agent_candidates: "{{ [ssh_agent_socket_base ~ '/gcr/ssh', ssh_agent_socket_base ~ '/openssh_agent'] if ssh_agent_channel == 'gcr' else [ssh_agent_socket_base ~ '/openssh_agent'] }}"
    ETC_FILES:
      - name: ssh-agent-env.zsh
        content: |
          # SSH agent rendezvous selection, projected by {{NAME}}.
          # Never clobber a live inherited SSH_AUTH_SOCK (agent forwarding,
          # session-provided agents); fill only when unset or stale.
          if [[ -z "${SSH_AUTH_SOCK:-}" || ! -S "${SSH_AUTH_SOCK}" ]]; then
            for __ssh_agent_cand in {{ ssh_agent_candidates | join(' ') }}; do
              if [[ -S "${__ssh_agent_cand}" ]]; then
                export SSH_AUTH_SOCK="${__ssh_agent_cand}"
                break
              fi
            done
            unset __ssh_agent_cand
          fi
      # POSIX twin for bash; paths contain no spaces so unquoted word
      # splitting in the for-list is safe.
      - name: ssh-agent-env.bash
        content: |
          # SSH agent rendezvous selection, projected by {{NAME}}.
          # Never clobber a live inherited SSH_AUTH_SOCK (agent forwarding,
          # session-provided agents); fill only when unset or stale.
          if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "${SSH_AUTH_SOCK}" ]; then
            for __ssh_agent_cand in {{ ssh_agent_candidates | join(' ') }}; do
              if [ -S "${__ssh_agent_cand}" ]; then
                export SSH_AUTH_SOCK="${__ssh_agent_cand}"
                break
              fi
            done
            unset __ssh_agent_cand
          fi
    BINS:
      - name: install-user.sh
        content: |
          command=${CONFIG_BLOCK_IN_FILE:-block-in-file}

          # migrate pre-overhaul footprints:
          # - the old block landed in ~/.zshrc (interactive only); the
          #   replacement lives in ~/.zshenv so login, interactive, and
          #   non-interactive shells (e.g. ssh remote commands) all select.
          sed -i '/^# {{NAME}} start$/,/^# {{NAME}} end$/d' "${HOME}/.zshrc" 2>/dev/null || true
          # - the old self-hosted unit shadowed the distro ssh-agent.service
          #   via ~/.config/systemd/user; retire it so distro units rule.
          if [ -e "${HOME}/.config/systemd/user/ssh-agent.service" ]; then
            systemctl --user disable --now ssh-agent.service 2>/dev/null || true
            rm -f "${HOME}/.config/systemd/user/ssh-agent.service"
            systemctl --user daemon-reload
          fi

          "$command" -n "${NAME:-{{NAME}}}" -C true -i "{{DIR}}/etc/ssh-agent-env.zsh" -o "${HOME}/.zshenv"
          "$command" -n "${NAME:-{{NAME}}}" -C true -i "{{DIR}}/etc/ssh-agent-env.bash" -o "${HOME}/.bashrc"
          "$command" -n "${NAME:-{{NAME}}}" -C true -i "{{DIR}}/etc/ssh-agent-env.bash" -o "${HOME}/.bash_profile"

          if [ "{{ ssh_agent_channel }}" = "openssh" ]; then
            systemctl --user unmask ssh-agent.socket ssh-agent.service 2>/dev/null || true
            systemctl --user enable --now ssh-agent.socket
          else
            systemctl --user disable --now ssh-agent.socket ssh-agent.service 2>/dev/null || true
            # masked, not merely disabled: package presets re-enable disabled
            # units on upgrade, and masking pulls the distro socket out of
            # the user-manager SSH_AUTH_SOCK race for good.
            systemctl --user mask ssh-agent.socket ssh-agent.service 2>/dev/null || true
            # a long-running agent exits nonzero under disable --now's SIGTERM
            # and would sit `failed` behind the mask; clear the residue.
            systemctl --user reset-failed ssh-agent.service 2>/dev/null || true
            # stopping the distro socket runs its ExecStopPre
            # `unset-environment SSH_AUTH_SOCK`, which also wipes gcr's live
            # publication from the user manager -- restore the gcr
            # rendezvous so user services keep their agent.
            systemctl --user set-environment SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh"
          fi
      - name: block-status.sh
        src: ../block-status.sh
        basedir: False
        compose: False
      - name: status-ssh-agent.sh
        basedir: False
        content: |
          status=0
          "{{DIR}}/bin/block-status.sh" "${NAME:-{{NAME}}}" "{{DIR}}/etc/ssh-agent-env.zsh" "${HOME}/.zshenv" || status=1
          "{{DIR}}/bin/block-status.sh" "${NAME:-{{NAME}}}" "{{DIR}}/etc/ssh-agent-env.bash" "${HOME}/.bashrc" || status=1
          "{{DIR}}/bin/block-status.sh" "${NAME:-{{NAME}}}" "{{DIR}}/etc/ssh-agent-env.bash" "${HOME}/.bash_profile" || status=1
          exit "$status"
    STATUSES:
      - status-ssh-agent.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
