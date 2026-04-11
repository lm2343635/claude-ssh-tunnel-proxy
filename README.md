# SSH Tunnel Proxy for Claude Code

Sets up an SSH SOCKS5 tunnel for maxOS, through a remote host and converts it to an HTTP proxy via Privoxy.

**Pipeline:** SSH tunnel (SOCKS5 on `:1080`) → Privoxy (HTTP on `:8118`) → shell env vars

## Prerequisites

- macOS with `ssh` (built-in)
- [Privoxy](https://www.privoxy.org/): `brew install privoxy`
- `curl` (for health checks)

## Configuration

Copy and edit the `.env` file in the project root:

```env
SSH_HOST="root@example.com"
SOCKS_PORT=1080
HTTP_PROXY_PORT=8118
PRIVOXY_CONFIG="/opt/homebrew/etc/privoxy/config"
LOG_FILE="/tmp/ssh-tunnel.log"
```

## Install

Please prepare the SSH server and setup SSH config before using this script.

```bash
make install
```

This symlinks the `proxy` command to `/usr/local/bin`, making it available system-wide.

## Usage

```bash
proxy start    # Start the tunnel
proxy stop     # Stop the tunnel
proxy status   # Check if the tunnel is running
proxy log      # View logs
proxy socks-on   # Enable macOS SOCKS proxy and git proxy (alias: proxy so)
proxy socks-off  # Disable macOS SOCKS proxy and git proxy (alias: proxy sf)
```

Set `NETWORK_SERVICE` in `.env` to match your network interface (default: `Wi-Fi`).

## Claude Settings

To use the proxy with Claude (claude.ai/code), add the following to your Claude settings:
Add proxy environment variables to your Claude Code settings at `~/.claude/settings.json`:

```json
{
  "env": {
    "HTTP_PROXY": "http://127.0.0.1:8118",
    "HTTPS_PROXY": "http://127.0.0.1:8118"
  }
}
```

### What `proxy start` does

1. Kill any existing SSH tunnel on the configured port
2. Create a new SSH dynamic port forward (SOCKS5 proxy)
3. Configure and restart Privoxy to convert SOCKS5 to HTTP
4. Run a health check to verify the tunnel is working
