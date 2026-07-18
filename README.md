# Tunnel Proxy — macOS app

A native SwiftUI **menu bar** app for an SSH SOCKS5 → HTTP proxy tunnel. It is
**fully self-contained**: the tunnel logic is implemented natively in Swift, and
Privoxy is bundled inside the app. After installing, it works with no external
scripts, no Homebrew, and no setup beyond entering your SSH host.

Pipeline: **`ssh -N -D` (SOCKS5)** → **bundled Privoxy (HTTP)** → app env / system proxy.

See [plan/gui-app-plan.md](plan/gui-app-plan.md) for the original design and mockups.

> Looking for the original shell scripts? A standalone bash CLI (`proxy start|stop|…`)
> lives in [cli/](cli/) — see [cli/README.md](cli/README.md).

## Build & run

```bash
xcodebuild -project TunnelProxy.xcodeproj -scheme TunnelProxy -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/TunnelProxy-*/Build/Products/Debug/TunnelProxy.app
```

Or open `TunnelProxy.xcodeproj` in Xcode and press ⌘R. Requires Xcode 15+ and macOS 14+.

## Release (signed DMG)

`release.sh` archives, exports a Developer ID-signed `.app` (team `X92HAV9XYP`),
verifies the signature of the app **and** the nested bundled privoxy, then builds
and signs a DMG at `build/TunnelProxy-<version>.dmg` with an `/Applications`
symlink for drag-install.

```bash
./release.sh                      # signed DMG (not notarized)
```

To notarize + staple (needed for other Macs to open it without Gatekeeper
warnings), provide Apple credentials. One-time setup of a keychain profile:

```bash
xcrun notarytool store-credentials TunnelProxyNotary \
    --apple-id "you@example.com" --team-id X92HAV9XYP --password <app-specific-password>
```

Then:

```bash
NOTARY_PROFILE=TunnelProxyNotary ./release.sh
```

(Or pass `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD` directly.) An
app-specific password is created at [https://appleid.apple.com](https://appleid.apple.com) → Sign-In &
Security → App-Specific Passwords.

The app, bundled privoxy binary, and dylibs are all signed with a secure
timestamp under the hardened runtime, so the bundle is notarization-ready.

It's a menu bar utility (`LSUIElement`) — no Dock icon. Look for the shield icon in
the menu bar.

## How it works

- **Menu bar popover** — active-server picker, status dot, exit IP,
  Connect/Disconnect, and toggles for the watchdog, macOS SOCKS proxy, and launch
  at login.
- **Settings → Servers** — manage multiple SSH server profiles (add/edit/delete,
  pick the active one). Each profile has a name, host, port, username, and an auth
  method.
- **Settings → Tunnel** — ports, network service, watchdog interval, and a runtime
  readiness check (bundled privoxy + `ssh` + `curl`).
- **Logs window** — tails the log file live with filtering, follow, and clear.

### SSH servers & authentication

All SSH connection data is owned by the app — nothing is shared with the CLI or
read from `~/.ssh/config` (unless a profile opts into agent/default-key auth).
Each server profile supports one of three auth methods:

| Method               | What it needs                           | Secret storage         |
| -------------------- | --------------------------------------- | ---------------------- |
| Default keys / agent | nothing (uses ssh-agent / default keys) | —                     |
| Private key file     | path to a key; optional passphrase      | passphrase in Keychain |
| Password             | the SSH password                        | password in Keychain   |

Passwords and key passphrases are stored in the **macOS Keychain** (service
`com.monstarlab.tunnelproxy`, keyed by the profile's UUID) — never in
`config.json`. `config.json` only records a `hasStoredSecret` flag.

For password/passphrase auth, ssh can't take a secret on the command line, so the
app uses a bundled `SSH_ASKPASS` helper (`Resources/helpers/askpass.sh`): ssh
invokes it when it needs the secret, and the helper echoes back what the app
placed in the `TP_ASKPASS_SECRET` environment variable for that one connection.
The secret is passed via the environment, never argv, so it never appears in `ps`.

Everything the app writes lives in `~/Library/Application Support/TunnelProxy/`:

| File             | Purpose                                  |
| ---------------- | ---------------------------------------- |
| `config.json`  | user configuration                       |
| `tunnel.log`   | ssh + privoxy output and status messages |
| `privoxy.conf` | generated fresh on each connect          |

## Self-contained runtime

- **ssh** and **curl** ship with macOS (`/usr/bin/...`) — always present.
- **Privoxy** is bundled at `TunnelProxy.app/Contents/Resources/privoxy/`. Its
  Homebrew dylib dependencies (`libpcre2-*`) are bundled alongside it and relocated
  to `@loader_path`, so it runs on a machine without Homebrew. A build phase
  re-signs the binary + dylibs with the app's identity (required by the hardened
  runtime).

The tunnel logic (start/stop/health-check/watchdog) is native Swift in
`TunnelEngine` — there are no shell scripts on disk.

### Updating the bundled Privoxy

The bundled binaries were produced from Homebrew's `privoxy` like so:

```bash
cp -L "$(brew --prefix)/sbin/privoxy" privoxy
cp -L "$(brew --prefix pcre2)/lib/libpcre2-8.0.dylib" .
cp -L "$(brew --prefix pcre2)/lib/libpcre2-posix.3.dylib" .
# repoint Homebrew paths at the sibling dylibs, then ad-hoc sign
install_name_tool -id @loader_path/libpcre2-8.0.dylib libpcre2-8.0.dylib
install_name_tool -id @loader_path/libpcre2-posix.3.dylib libpcre2-posix.3.dylib
install_name_tool -change <old-pcre2-8-path> @loader_path/libpcre2-8.0.dylib libpcre2-posix.3.dylib
install_name_tool -change <old-pcre2-8-path> @loader_path/libpcre2-8.0.dylib privoxy
install_name_tool -change <old-posix-path>  @loader_path/libpcre2-posix.3.dylib privoxy
codesign -s - --force libpcre2-8.0.dylib libpcre2-posix.3.dylib privoxy
```

Then drop the three files into `TunnelProxy/Resources/privoxy/`. (Verify with
`otool -L privoxy` — no path should point into `/opt/homebrew`.)

## Not sandboxed

App Sandbox is **disabled** (`TunnelProxy.entitlements`): the app spawns `ssh`,
the bundled `privoxy`, and `networksetup`. The macOS SOCKS proxy toggle uses
`networksetup`, which needs admin rights — the app prompts via `osascript`.

For distribution beyond your own machine, sign and notarize with a Developer ID
(the bundled privoxy must be signed with the same identity — the signing build
phase handles that automatically when `EXPANDED_CODE_SIGN_IDENTITY` is set).

## Layout

```
.
  TunnelProxy.xcodeproj
  TunnelProxy/
    TunnelProxyApp.swift          # @main, MenuBarExtra + Settings + Logs scenes
    Controllers/
      AppPaths.swift              # Application Support locations + bundled binary paths
      ServerProfile.swift         # one SSH server: host/port/user/auth method/key path
      TunnelConfig.swift          # [ServerProfile] + selected id + tunnel settings (JSON)
      KeychainStore.swift         # per-server passwords/passphrases in the Keychain
      NetworkServices.swift       # macOS network service discovery for the SOCKS toggle
      SpeedMonitor.swift          # live upload/download throughput sampling
      TunnelEngine.swift          # native ssh -D + bundled privoxy + watchdog + askpass
      TunnelController.swift      # observable state, server CRUD, status polling, login
      MenuBarRenderer.swift       # menu bar icon/title rendering
      ProcessRunner.swift         # generic Process wrapper + privileged (osascript) runs
      LogTailer.swift             # follows the log file via DispatchSource
    Views/
      MenuBarView.swift           # popover + server picker
      SettingsView.swift          # Servers / Tunnel / Advanced / About tabs
      ServersView.swift           # server list + add/edit editor sheet
      LogsView.swift              # live log viewer
      ManualView.swift            # in-app user guide (bundled HTML)
    Resources/
      privoxy/                    # bundled privoxy binary + relocated dylibs
      helpers/askpass.sh          # SSH_ASKPASS helper for password/passphrase auth
      manual/                     # bundled user-guide HTML (en + zh-Hans)
    Assets.xcassets, Info.plist, TunnelProxy.entitlements
  release.sh                      # build + sign (+ notarize) a distributable DMG
  ExportOptions.plist             # xcodebuild -exportArchive options
  icon/                           # app icon master + generator
  plan/                           # design docs + mockups
  cli/                            # standalone bash CLI (proxy start|stop|…)
```
