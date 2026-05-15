#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

make -n hotdog-build >/tmp/hotdog-build.dryrun 2>/tmp/hotdog-build.err || {
  cat /tmp/hotdog-build.err >&2
  fail "make hotdog-build should exist and dry-run successfully"
}

grep -q "hotdog-ticket-assistant:local" docker-compose.yml || \
  fail "docker-compose.yml should define the hotdog-ticket-assistant:local image tag"

if grep -q 'ENTRYPOINT \["pi"\]' Dockerfile; then
  fail "Dockerfile should not force pi as ENTRYPOINT; Hotdog must be able to run sleep infinity"
fi

grep -q 'CMD \["pi"\]' Dockerfile || \
  fail "Dockerfile should keep pi as the default command for interactive compose usage"

grep -q 'PARANOID_MODE=\${PARANOID_MODE:-true}' docker-compose.yml || \
  fail "pi-agent should pass PARANOID_MODE=true by default"

grep -q 'user: "\${HOST_UID:-1000}:\${HOST_GID:-1000}"' docker-compose.yml || \
  fail "pi-agent should keep UID/GID mapping for host-owned files"

if awk '/environment:/,/secrets:/' docker-compose.yml | grep -q 'GITHUB_TOKEN'; then
  fail "pi-agent environment must not expose GITHUB_TOKEN"
fi

grep -q 'github_token:' docker-compose.yml || \
  fail "github token should remain available through Docker secrets"

grep -q 'hotdog-ticket-assistant:local' README.md || \
  fail "README should document the Hotdog image tag"

grep -q 'make hotdog-build' README.md || \
  fail "README should document the Hotdog build command"

for target in hotdog-gateway-up hotdog-gateway-down hotdog-gateway-status; do
  make -n "$target" >/tmp/$target.dryrun 2>/tmp/$target.err || {
    cat /tmp/$target.err >&2
    fail "make $target should exist and dry-run successfully"
  }
done

grep -q 'name: hotdog_agent_gateway' docker-compose.yml || \
  fail "gateway network should use stable hotdog_agent_gateway name"

grep -q 'api.minimax.io' config/hosts.json || fail "gateway should allow MiniMax"
grep -q 'openrouter.ai' config/hosts.json || fail "gateway should allow OpenRouter"
grep -q 'registry.npmjs.org' config/hosts.json || fail "gateway should allow npm registry"

status_json="$(MAKEFLAGS= make hotdog-gateway-status 2>/tmp/gateway-status.err)" || {
  cat /tmp/gateway-status.err >&2
  fail "make hotdog-gateway-status should run"
}
node -e '
const status = JSON.parse(process.argv[1]);
for (const key of ["running", "containerName", "network", "dnsIp", "controlPlaneUrl"]) {
  if (!(key in status)) throw new Error(`missing ${key}`);
}
if (status.network !== "hotdog_agent_gateway") throw new Error("wrong network");
if (status.dnsIp !== "172.53.0.53") throw new Error("wrong dns");
' "$status_json" || fail "gateway status should be valid JSON contract"

echo "ok - hotdog image, gateway, command override, vault defaults, and docs are configured"
