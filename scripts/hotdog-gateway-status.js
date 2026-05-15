#!/usr/bin/env node
const { execFileSync } = require('node:child_process');

const containerName = process.env.HOTDOG_GATEWAY_CONTAINER || 'hotdog_agent_gateway';
const network = process.env.HOTDOG_GATEWAY_NETWORK || 'hotdog_agent_gateway';
const dnsIp = process.env.HOTDOG_GATEWAY_DNS_IP || '172.53.0.53';
const controlPlaneUrl = process.env.HOTDOG_GATEWAY_CONTROL_PLANE_URL || 'http://localhost:58080';

let running = false;
let status = 'missing';
try {
  const out = execFileSync('docker', ['inspect', containerName, '--format', '{{.State.Running}} {{.State.Status}}'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  const [runningText, statusText] = out.split(/\s+/, 2);
  running = runningText === 'true';
  status = statusText || (running ? 'running' : 'stopped');
} catch {
  running = false;
  status = 'missing';
}

process.stdout.write(JSON.stringify({
  running,
  status,
  containerName,
  network,
  dnsIp,
  controlPlaneUrl,
}) + '\n');
