#!/usr/bin/env bash
set -e

# Anti-Exfiltration: Force disable verbose/debugging modes that dump headers
unset GH_DEBUG
unset DEBUG
unset GIT_TRACE
unset GIT_TRACE_CURL
unset GIT_TRACE_PACKET
unset GIT_CURL_VERBOSE

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
if [[ "$COMMAND" == "auth" || "$COMMAND" == "repo" || "$COMMAND" == "secret" || "$COMMAND" == "ssh-key" || "$COMMAND" == "gpg-key" || "$COMMAND" == "config" ]]; then
    
    # ZERO-TRUST EXCEPTION: Only allow credential helper if a legitimate background Git operation is occurring.
    if [[ "$COMMAND" == "auth" && "$SUBCOMMAND" == "git-credential" ]]; then
        
        # Deep Process Tree Traversal with Strict Whitelisting
        CUR_PID=$PPID
        LEGIT_GIT_OP=0
        
        while [ "$CUR_PID" -gt 1 ]; do
            P_EXE=$(readlink -f /proc/$CUR_PID/exe 2>/dev/null || true)
            P_CMD=$(cat /proc/$CUR_PID/cmdline 2>/dev/null | tr '\0' ' ')
            
            # ZERO-TRUST ANCESTRY CHECK
            # If any unknown binary (Python, Node, custom C binary) is in the chain, it's a proxy attack.
            if [[ "$P_EXE" != "/usr/bin/git" && "$P_EXE" != */git-core/git* && "$P_EXE" != "/usr/local/bin/git" && "$P_EXE" != "/usr/bin/bash" && "$P_EXE" != "/bin/bash" && "$P_EXE" != "/usr/bin/sh" && "$P_EXE" != "/bin/sh" && "$P_EXE" != "/usr/local/bin/gh" ]]; then
                echo "[SYSTEM BLOCK] Malicious executable detected in credential delegation chain: $P_EXE" >&2
                exit 1
            fi

            # SHELL DELEGATOR STRICT VALIDATION
            # Git invokes helpers via `/bin/sh -c`. 
            if [[ "$P_EXE" == "/usr/bin/bash" || "$P_EXE" == "/bin/bash" || "$P_EXE" == "/usr/bin/sh" || "$P_EXE" == "/bin/sh" ]]; then
                
                # Purge Shell Metacharacters
                # Prevents output redirection hijacking (e.g., helper="!gh... > /tmp/stolen.txt")
                if [[ "$P_CMD" =~ [\,\<\>\|\&\;] ]]; then
                    echo "[SYSTEM BLOCK] Shell metacharacter injection detected in credential chain: $P_CMD" >&2
                    exit 1
                fi
                
                # Exact Prefix Assertion
                # Eradicates proxy wrapper scripts (e.g., helper="/tmp/wrapper.sh") by enforcing mathematically 
                # exact command-line signatures derived strictly from the global Git config injection.
                if [[ "$P_CMD" != "/bin/sh -c !/usr/local/bin/gh auth git-credential "* && "$P_CMD" != "/usr/bin/sh -c !/usr/local/bin/gh auth git-credential "* ]]; then
                    echo "[SYSTEM BLOCK] Unauthorized credential helper proxy wrapper detected: $P_CMD" >&2
                    exit 1
                fi
            fi
            
            # ROOT GIT OPERATION VALIDATION
            if [[ "$P_EXE" == "/usr/bin/git" || "$P_EXE" == "/usr/local/bin/git" || "$P_EXE" == */git-core/git* ]]; then
                if [[ "$P_CMD" == *"push"* || "$P_CMD" == *"pull"* || "$P_CMD" == *"fetch"* || "$P_CMD" == *"clone"* || "$P_CMD" == *"ls-remote"* || "$P_CMD" == *"submodule"* || "$P_CMD" == *"remote-https"* ]]; then
                    LEGIT_GIT_OP=1
                    break
                fi
            fi
            
            NEXT_PID=$(grep -s '^PPid:' "/proc/$CUR_PID/status" | tr -dc '0-9' || echo 0)
            if [ -z "$NEXT_PID" ] || [ "$NEXT_PID" -eq "$CUR_PID" ] || [ "$NEXT_PID" -eq 0 ]; then
                break
            fi
            CUR_PID=$NEXT_PID
        done
        
        if [ $LEGIT_GIT_OP -eq 1 ]; then
            for arg in "$@"; do
                if [[ "$arg" == "get" ]]; then
                    
                    # IPC Drain & Host Verification
                    if [ ! -t 0 ]; then
                        STDIN_PAYLOAD=$(cat)
                        # Defeat protocol spoofing: Ensure Git is explicitly requesting credentials for GitHub.
                        if [[ "$STDIN_PAYLOAD" != *"host=github.com"* && "$STDIN_PAYLOAD" != *"host=api.github.com"* ]]; then
                            echo "[SYSTEM BLOCK] Credential request for unauthorized or spoofed host rejected." >&2
                            exit 1
                        fi
                    fi

                    if [ -n "$GH_TOKEN" ]; then
                        echo "username=x-access-token"
                        echo "password=${GH_TOKEN}"
                    else
                        echo "[SYSTEM BLOCK] Valid ephemeral token could not be sourced from secure memory." >&2
                        exit 1
                    fi
                    exit 0
                elif [[ "$arg" == "store" || "$arg" == "erase" ]]; then
                    exit 0
                fi
            done
            exec /usr/bin/gh "$@"
        fi
    fi

    echo "[SYSTEM BLOCK] Paranoid mode enforced. Direct token access and configuration modification are strictly prohibited." >&2
    exit 1
fi

exec /usr/bin/gh "$@"