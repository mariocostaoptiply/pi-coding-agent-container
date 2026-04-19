#!/usr/bin/env bash
set -e

COMMAND=$1

if [ "${PARANOID_MODE}" = "true" ]; then
    if [[ "$COMMAND" == "auth" || "$COMMAND" == "repo" || "$COMMAND" == "secret" || "$COMMAND" == "ssh-key" || "$COMMAND" == "gpg-key" ]]; then
        echo "[SYSTEM BLOCK] Paranoid mode is active. The agent is not authorized to execute gh $COMMAND."
        exit 1
    fi
fi

exec /usr/bin/gh "$@"