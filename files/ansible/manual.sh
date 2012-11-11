#!/bin/sh

mkdir -p ~/.local/opt ~/.local/bin ~/.config/ansible
[[ ! -d ~/.local/opt/ansible ]] && git clone https://github.com/ansible/ansible.git ~/.local/opt/ansible
[[ ! -e ~/.ansible/hosts.localhost ]] && echo 127.0.0.1 >> ~/.ansible/hosts.localhost
[[ ! -e ~/.ansible/hosts ]] && ln -s ~/.ansible/hosts.localhost ~/.ansible/hosts
[[ ! -e ~/.ansible/env.ansible ]] && cp env.ansible ~/.ansible/env.ansible
