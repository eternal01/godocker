#!/usr/bin/env bash
set -e

if [ -x /usr/sbin/sshd ]; then
    # /run is tmpfs in Debian — the sshd privsep directory baked into the
    # image layer is gone on every container start. Recreate it before launch,
    # and gate on sshd binary presence (the old check, `[ -d /run/sshd ]`,
    # was the root cause of "sshd down after every restart").
    mkdir -p /run/sshd

    mkdir -p "${WORKSPACE_HOME}/.ssh"
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.ssh"
    chmod 700 "${WORKSPACE_HOME}/.ssh"

    if [ -f "${WORKSPACE_HOME}/.ssh/authorized_keys" ]; then
        chown "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.ssh/authorized_keys"
        chmod 600 "${WORKSPACE_HOME}/.ssh/authorized_keys"
    fi

    # -E routes sshd logs to a file so a start failure is debuggable without
    # exec'ing into the container. sshd is daemonized, so it's a child of
    # entrypoint, not PID 1 — fine for the failure mode we're fixing
    # ("never starts") but does not cover "crashes later".
    /usr/sbin/sshd -E /var/log/sshd.log || echo "[workspace-entrypoint] sshd failed to start (see /var/log/sshd.log)"
fi

if [ -d "${WORKSPACE_HOME}/.cache/mise" ]; then
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.cache"
fi

if [ -d "${WORKSPACE_HOME}/.config/mise" ]; then
    chown -R "${WORKSPACE_USER}:${WORKSPACE_USER}" "${WORKSPACE_HOME}/.config"
fi

# Inform the user when a project has a mise configuration. Installation is
# explicit so entering a directory never downloads a toolchain unexpectedly.
if [ -f "${WORKSPACE_HOME}/.tool-versions" ] || [ -f "${WORKSPACE_HOME}/.mise.toml" ] || [ -f "/workspace/mise.toml" ]; then
    echo "[workspace-entrypoint] mise configuration detected. Consider running 'mise install' inside the container."
fi

exec gosu "${WORKSPACE_USER}" "$@"
