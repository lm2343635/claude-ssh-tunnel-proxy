#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "${ENV_FILE}" ]; then
    echo "Config file not found: ${ENV_FILE}"
    exit 1
fi

source "${ENV_FILE}"

# Check dependencies
if ! command -v privoxy &>/dev/null; then
    echo "privoxy not found, install with: brew install privoxy"
    exit 1
fi

if [ ! -f "${PRIVOXY_CONFIG}" ]; then
    echo "privoxy config not found at ${PRIVOXY_CONFIG}"
    exit 1
fi

# Start SSH tunnel
echo "$(date): Starting SSH tunnel..." >> "$LOG_FILE"
pkill -f "ssh.*-D ${SOCKS_PORT}.*${SSH_HOST}" 2>/dev/null
sleep 1
ssh -fNC \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=10 \
    -D ${SOCKS_PORT} ${SSH_HOST}

sleep 2

# Start Privoxy
cat > "${PRIVOXY_CONFIG}" << EOF
forward-socks5 / 127.0.0.1:${SOCKS_PORT} .
listen-address 127.0.0.1:${HTTP_PROXY_PORT}
EOF
brew services restart privoxy >> "$LOG_FILE" 2>&1
sleep 2

# Health check
if curl -s --max-time 5 -x http://127.0.0.1:${HTTP_PROXY_PORT} \
    https://api.anthropic.com/v1/models 2>/dev/null | grep -q "authentication_error"; then
    echo "Tunnel + proxy OK"
    echo "$(date): Tunnel + proxy started successfully" >> "$LOG_FILE"
elif curl -s --max-time 5 --socks5-hostname 127.0.0.1:${SOCKS_PORT} \
    https://api.ipify.org 2>/dev/null | grep -q "."; then
    echo "Tunnel OK but proxy failed"
    echo "$(date): Tunnel OK but proxy failed" >> "$LOG_FILE"
else
    echo "Tunnel failed to start"
    echo "$(date): Tunnel failed to start" >> "$LOG_FILE"
fi

echo "Log: tail -f $LOG_FILE"
