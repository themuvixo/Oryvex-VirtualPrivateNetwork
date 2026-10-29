# OryvexVPN 2.5.0 (Created by Muvixo)

## Fixed
- **Android froze on "Identity" with an empty Activity log.** The app subscribed to the
  service's event stream in `AndroidBackend()`'s constructor, which ran before Flutter's
  bindings existed, so the subscription silently failed and no core line ever reached the UI.
  The stream now attaches lazily after `WidgetsFlutterBinding.ensureInitialized()`, and every
  line carries a sequence number with a pull fallback (`since(seq)`), so logs and progress keep
  flowing even if the stream is ever late. Notification permission is now asked after the VPN
  consent dialog instead of on top of it.
- **Desktop font loading.** The bundled Inter / Inter Display / JetBrains Mono files were
  variable-font instances whose name tables all said "Inter Regular" (same PostScript name,
  REGULAR flag even on Bold, leftover STAT axes). DirectWrite on Windows merged or rejected
  them, so weights collapsed or fell back to system fonts. All 11 files now have correct
  family/style names, weight classes, fsSelection/macStyle bits, and no stale STAT table.
- Stage hint when a step takes unusually long (e.g. Cloudflare registration on filtered networks).

## Changed
- Renamed the app to **OryvexVPN** (window, launcher label, exe `OryvexVPN.exe`,
  `OryvexVPNLite.exe`, notification, VPN session, release artifacts). The engine/CLI keeps the
  name `oryvexcore`, and the settings folder stays `%APPDATA%\OryvexCore` so saved identities survive.
- "Created by Muvixo" in the app, About, Windows file properties and release notes.
- New apple.com-style UI: frosted top nav (desktop) / floating glass tab bar (phones), big tight
  headlines with blur-in text changes, bento grid with live speed graphs, segmented controls,
  inset grouped settings, licenses page.
- New connection animation: the logo's orbit ring with the core circling it as a comet, sonar
  rings while searching, ring fills with progress, closes with a shock ring on connect, then breathes.
- Shared-axis page transitions between tabs (state kept), custom route transitions, staggered
  reveals, press feedback, keyboard shortcuts Ctrl+1/2/3. Respects "reduce motion".
