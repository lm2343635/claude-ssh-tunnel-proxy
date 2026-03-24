# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file bash project (`tunnel-proxy.sh`) that sets up an SSH SOCKS5 tunnel through a remote host, converts it to an HTTP proxy via Privoxy, and exports proxy environment variables for the current shell session.

## Architecture

The script is designed to be **sourced** (not executed) so that `set_proxy`/`unset_proxy` can modify the calling shell's environment variables. It uses `return` (not `exit`) for error handling.

Pipeline: **SSH tunnel (SOCKS5 on :1080)** -> **Privoxy (HTTP on :8118)** -> **shell env vars**

Key components:
- SSH dynamic port forwarding (`-D`) creates a SOCKS5 proxy
- Privoxy converts SOCKS5 to HTTP proxy (config at `/opt/homebrew/etc/privoxy/config`)
- Background watchdog loop reconnects the tunnel if it drops, falling back to direct connection
- Health checks use `api.ipify.org` (tunnel) and `api.anthropic.com` (proxy)

## Usage

```bash
source tunnel-proxy.sh   # Must be sourced, not executed
tail -f /tmp/ssh-tunnel.log  # View logs
```

## Dependencies

- `ssh` (macOS built-in)
- `privoxy` (`brew install privoxy`)
- `curl` (for health checks)
