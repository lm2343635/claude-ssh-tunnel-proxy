#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
WATCHDOG_PID_FILE="/tmp/ssh-tunnel-watchdog.pid"

if [ ! -f "${ENV_FILE}" ]; then
    echo "Config file not found: ${ENV_FILE}"
    exit 1
fi

source "${ENV_FILE}"

if [ -f "${WATCHDOG_PID_FILE}" ]; then
    kill "$(cat "${WATCHDOG_PID_FILE}")" 2>/dev/null
    rm -f "${WATCHDOG_PID_FILE}"
fi

pkill -f "ssh.*-D ${SOCKS_PORT}.*${SSH_HOST}" 2>/dev/null
brew services stop privoxy 2>/dev/null

echo "Tunnel and proxy stopped"
echo "$(date): Tunnel and proxy stopped" >> "$LOG_FILE"
