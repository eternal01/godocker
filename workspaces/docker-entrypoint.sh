#!/usr/bin/env bash
set -e

if [ -d /run/sshd ]; then
    mkdir -p "${WORKSPACE_HOME}/.ssh"
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.ssh"
    chmod 700 "${WORKSPACE_HOME}/.ssh"

    if [ -f "${WORKSPACE_HOME}/.ssh/authorized_keys" ]; then
        chown "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.ssh/authorized_keys"
        chmod 600 "${WORKSPACE_HOME}/.ssh/authorized_keys"
    fi

    /usr/sbin/sshd
fi

# Ensure ownership of mise cache/data directories
if [ -d "${WORKSPACE_HOME}/.local/share/mise" ]; then
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.local/share/mise"
fi

if [ -d "${WORKSPACE_HOME}/.cache/mise" ]; then
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.cache"
fi

if [ -d "${WORKSPACE_HOME}/.config/mise" ]; then
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.config"
fi

# Auto-install languages if mise config is present ( lazy-load / on-startup strategy )
if [ -f "${WORKSPACE_HOME}/.tool-versions" ] || [ -f "${WORKSPACE_HOME}/.mise.toml" ] || [ -f "/workspace/mise.toml" ]; then
    echo "[workspace-entrypoint] mise configuration detected. Consider running 'mise install' inside the container."
fi

exec gosu "${WORKSPACE_USER}" "$@"
