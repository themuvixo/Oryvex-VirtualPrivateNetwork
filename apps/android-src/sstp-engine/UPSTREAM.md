# SSTP engine provenance

- Upstream repository: https://github.com/hoang-rio/Open-SSTP-Client
- Vendored source revision: `af677f17481690eabd04327f5002841151479e1d` (verified GitHub commit, 2026-10-19)
- The engine source is vendored in this directory; builds do not fetch a moving branch.
- License: MIT, copyright KOBAYASHI Ittoku; see `LICENSE`.
- Adaptation: the upstream protocol/PPP/TLS sources run through OryvexVPN's one declared `OryvexVpnService`. The module manifest intentionally declares no SSTP VpnService or tile service.
- TLS certificate-chain and hostname verification are explicitly enabled for VPN Gate connections; no insecure verifier is installed.
- Auth is configured to MS-CHAPv2 only with the documented VPN Gate credentials.
- Upstream says SoftEther/VPN Azure are its officially supported targets; VPN Gate relay compatibility remains to be verified on Android hardware.
