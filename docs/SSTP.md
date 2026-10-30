# SSTP and VPN Gate

OryvexVPN supports VPN Gate MS-SSTP on Windows through Windows' built-in SSTP dialer, and on Android through the vendored MIT-licensed Open-SSTP engine adapted to run inside OryvexVPN's existing `OryvexVpnService`. The engine is not registered as a second Android VPN service; its PPP-assigned interface uses the one service the user already approved.

For VPN Gate, the app uses the exact `*.opengw.net` DNS hostname and listed TCP port, preserving TLS hostname verification. It configures the documented username and password `vpn` / `vpn`, with MS-CHAPv2 as the PPP authentication method. Certificate chain and hostname verification stay enabled by default; no global trust-all callback is installed.

The upstream engine identifies SoftEther/VPN Azure as its officially supported targets. VPN Gate relay interoperability has not yet been confirmed by a live Android device/relay run. Public volunteer relays can be offline or incompatible, and their privacy practices are outside OryvexVPN's control.

VPN Gate's own Android how-to lists the Android connection approaches it documents; it is not the source of OryvexVPN's Android SSTP implementation. The separate VPN Gate SSTP guide provides the hostname, port and credential requirements used here.

Upstream source and MIT notice: `apps/android-src/sstp-engine/UPSTREAM.md` and `LICENSE`.


## Server list refresh behavior

The app does not automatically fetch VPN Gate's directory when connecting or retrying. It uses the bundled list or the last saved list, so a timeout reaching `vpngate.net` cannot stall SSTP connection attempts. Use **Refresh list** in Settings when you want to fetch an updated directory.
