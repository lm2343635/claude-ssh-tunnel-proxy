#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
WATCHDOG_PID_FILE="/tmp/ssh-tunnel-watchdog.pid"
WATCHDOG_INTERVAL=30

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

start_ssh_tunnel() {
    pkill -f "ssh.*-D ${SOCKS_PORT}.*${SSH_HOST}" 2>/dev/null
    sleep 1
    ssh -fNC \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=10 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=10 \
        -D ${SOCKS_PORT} ${SSH_HOST}
}

# Start SSH tunnel
echo "$(date): Starting SSH tunnel..." >> "$LOG_FILE"
start_ssh_tunnel

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

# Optional watchdog for auto-reconnect
if [ "$1" = "--always" ]; then
    if [ -f "${WATCHDOG_PID_FILE}" ]; then
        kill "$(cat "${WATCHDOG_PID_FILE}")" 2>/dev/null
        rm -f "${WATCHDOG_PID_FILE}"
    fi

    (
        while true; do
            sleep "${WATCHDOG_INTERVAL}"
            if ! curl -s --max-time 5 --socks5-hostname 127.0.0.1:${SOCKS_PORT} \
                https://api.ipify.org 2>/dev/null | grep -qE "[0-9]+\.[0-9]+"; then
                echo "$(date): Tunnel down, reconnecting..." >> "$LOG_FILE"
                start_ssh_tunnel
            fi
        done
    ) &
    WATCHDOG_PID=$!
    echo "${WATCHDOG_PID}" > "${WATCHDOG_PID_FILE}"
    echo "Watchdog enabled (PID ${WATCHDOG_PID}), checking every ${WATCHDOG_INTERVAL}s"
    echo "$(date): Watchdog started (PID ${WATCHDOG_PID})" >> "$LOG_FILE"
fi

echo "Log: tail -f $LOG_FILE"
