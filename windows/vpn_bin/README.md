# Windows VPN binaries

Status of each protocol's Windows backend:

| Protocol | Status | Backend |
|---|---|---|
| OpenVPN | ✅ Bundled and verified working (real tunnel to a live server, confirmed via external IP check) | `windows_vpn_service.dart` |
| WireGuard | ✅ Bundled and working | `windows_wireguard_service.dart` |
| V2Ray / Xray | ✅ Bundled and working | `windows_v2ray_service.dart` |
| OpenConnect | ❌ Not supported — no Windows binary available | — |

The `openvpn.exe` here (2.7.5.0) is the official, DigiCert-signed OpenVPN
Inc. binary — verify with
`Get-AuthenticodeSignature vpn_bin\openvpn.exe` before trusting any
future replacement of this file.

## What's already here

- `wintun.dll` (amd64) — from https://www.wintun.net, the WireGuard
  project's userspace-loadable TUN driver. Used by OpenVPN's
  `--windows-driver wintun` mode.
- `wireguard.exe` / `wg.exe` — official WireGuard for Windows, downloaded
  and installed from `download.wireguard.com` (verified reachable,
  unlike OpenVPN's domain — see below), then copied out of
  `C:\Program Files\WireGuard\`.
- `xray.exe`, `geoip.dat`, `geosite.dat` — official Xray-core Windows
  release, from XTLS/Xray-core's GitHub Releases. Runs as a local SOCKS5
  proxy (127.0.0.1:10808); `WindowsV2RayService` points the Windows
  system proxy at it. No elevation needed for this protocol.

## How openvpn.exe got here

`openvpn.net`'s own download domains (`swupdate.openvpn.net` /
`build.openvpn.org`) were unreachable from this sandboxed dev
environment — every distribution channel (direct download, PowerShell,
Chocolatey, Scoop) resolves to the same blocked/reset origin, most
likely Cloudflare's edge rejecting the datacenter-class exit IP of the
VPN used to route around the network restriction, not a Bahrain-level
block specifically (confirmed: DNS resolves and TCP connects fine, only
the TLS handshake gets reset, identically across 4 different HTTP
client stacks).

The binary was instead sourced from a legitimately-installed copy of
another VPN app (BlazeVPN) already present on the dev machine, which
bundles the same official, unmodified OpenVPN Windows Community
release as part of its own installer — verified authentic via
Authenticode signature (`OpenVPN Inc.`, issued by DigiCert) and file
version metadata (2.7.5.0, "The OpenVPN Project") before copying.

If you ever need to replace it, get it from the official installer at
https://openvpn.net/community-downloads/, copy `openvpn.exe` plus its
three DLLs (`libcrypto-3-x64.dll`, `libssl-3-x64.dll`,
`libpkcs11-helper-1.dll`) from the install's `bin\` folder into this
directory, and rebuild (`flutter build windows` — the CMake install
step copies everything here next to the built `axe_vpn.exe`). Do
**not** source it from an unofficial mirror — it runs elevated and
handles VPN credentials.

## Why some of this needs elevation and some doesn't

- OpenVPN and WireGuard both create a real TUN network adapter, which
  requires administrator rights — both trigger one UAC prompt per
  connect (`_startElevated`/`_runElevated` in their respective service
  files).
- V2Ray/Xray runs as a plain userspace SOCKS proxy with the system proxy
  setting pointed at it (a per-user registry change) — no elevation
  needed, but it only covers proxy-aware apps, not raw sockets, unlike
  the other two.
