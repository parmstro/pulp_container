#!/bin/bash
# Ansible playbook wrapper that uses the password file if available

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PASSWORD_FILE="$SCRIPT_DIR/.claude.password.txt"

if [ -f "$PASSWORD_FILE" ]; then
    # Use password file
    export ANSIBLE_PASSWORD=$(cat "$PASSWORD_FILE")
    ansible-playbook "$@" --extra-vars "ansible_ssh_pass=$ANSIBLE_PASSWORD"
else
    # Fall back to interactive password prompt
    ansible-playbook "$@" --ask-pass
fi
