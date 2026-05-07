#!/usr/bin/env bash
set -e

COMMAND=""
SUBCOMMAND=""

# Secure Parser: Ignore flags (starting with -) to find the actual commands
for arg in "$@"; do
    if [[ "$arg" != -* ]]; then
        if [ -z "$COMMAND" ]; then
            COMMAND="$arg"
        elif [ -z "$SUBCOMMAND" ]; then
            SUBCOMMAND="$arg"
            break
        fi
    fi
done

# Normalize to lowercase to prevent 'Auth' bypass
COMMAND="${COMMAND,,}"
SUBCOMMAND="${SUBCOMMAND,,}"

# Strict filter for authentication, state-altering, and configuration commands
# Zero-Trust Enforcement: Environmental overrides (PARANOID_MODE) have been purged.
if [[ "$COMMAND" == "auth" || "$COMMAND" == "repo" || "$COMMAND" == "secret" || "$COMMAND" == "ssh-key" || "$COMMAND" == "gpg-key" || "$COMMAND" == "config" ]]; then
    
    # ZERO-TRUST EXCEPTION: Only allow credential helper if a legitimate background Git operation is occurring.
    if [[ "$COMMAND" == "auth" && "$SUBCOMMAND" == "git-credential" ]]; then
        
        # Deep Process Tree Traversal
        # We traverse upward indefinitely to locate the true root Git command,
        # bypassing proxy sub-shells and git's internal credential sub-processes.
        CUR_PID=$PPID
        LEGIT_GIT_OP=0
        
        while [ "$CUR_PID" -gt 1 ]; do
            P_EXE=$(readlink -f /proc/$CUR_PID/exe 2>/dev/null || true)
            P_CMD=$(cat /proc/$CUR_PID/cmdline 2>/dev/null | tr '\0' ' ')
            
            if [[ "$P_EXE" == "/usr/bin/git" || "$P_EXE" == /usr/lib/git-core/git* ]]; then
                # Identify if the orchestrating parent is a high-level network operation
                if [[ "$P_CMD" == *"push"* || "$P_CMD" == *"pull"* || "$P_CMD" == *"fetch"* || "$P_CMD" == *"clone"* || "$P_CMD" == *"ls-remote"* || "$P_CMD" == *"submodule"* || "$P_CMD" == *"remote-https"* ]]; then
                    LEGIT_GIT_OP=1
                    break
                fi
            fi
            
            NEXT_PID=$(awk '/^PPid:/ {print $2}' /proc/$CUR_PID/status 2>/dev/null || echo 0)
            if [ -z "$NEXT_PID" ] || [ "$NEXT_PID" -eq "$CUR_PID" ] || [ "$NEXT_PID" -eq 0 ]; then
                break
            fi
            CUR_PID=$NEXT_PID
        done
        
        if [ $LEGIT_GIT_OP -eq 1 ]; then
            exec /usr/bin/gh "$@"
        fi
    fi

    echo "[SYSTEM BLOCK] Paranoid mode enforced. Direct token access and configuration modification are strictly prohibited." >&2
    exit 1
fi

exec /usr/bin/gh "$@"