import 'package:flutter/material.dart';

import '../core/args.dart';
import '../core/controller.dart';
import '../core/settings.dart';
import 'theme.dart';
import 'widgets/brand.dart';
import 'widgets/motion.dart';
import 'widgets/section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final s = c.settings;
        void set(void Function(CoreSettings x) edit) => c.updateSettings(edit);
        int port(String v, int fallback) {
          final p = int.tryParse(v.trim());
          return p != null && p > 0 && p < 65536 ? p : fallback;
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, pad.top + 10, 20, pad.bottom + 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PageTitle(eyebrow: 'Make it yours', title: 'Settings'),
                  _Dirty(controller: c),
                  OxSection(
                    title: 'Appearance',
                    children: [
                      SwitchRow(
                        title: 'Dark mode',
                        subtitle: 'Use a dark interface across OryvexVPN',
                        value: s.darkTheme,
                        onChanged: (v) => set((x) => x.darkTheme = v),
                      ),
                    ],
                  ),
                  OxSection(
                    title: 'Connection',
                    footer: 'Changes apply the next time you connect.',
                    children: [
                      ChoiceRow(
                        label: 'Protocol',
                        options: Choices.protocolsFor(sstp: c.supportsSstp),
                        value: s.protocol,
                        hint: Choices.protocolHints[s.protocol],
                        onChanged: (v) => set((x) => x.protocol = v),
                      ),
                      if (!s.torOnly && (usesMasqueCarrier(s.protocol) || s.protocol == 'auto'))
                        ChoiceRow(
                          label: 'MASQUE carrier',
                          segmented: true,
                          options: Choices.transports,
                          value: s.transport,
                          hint: Choices.transportHints[s.transport],
                          onChanged: (v) => set((x) => x.transport = v),
                        ),
                      ChoiceRow(
                        label: 'Scan',
                        options: Choices.scans,
                        value: s.scan,
                        hint: Choices.scanHints[s.scan],
                        onChanged: (v) => set((x) => x.scan = v),
                      ),
                      ChoiceRow(
                        label: 'Obfuscation',
                        options: Choices.noizes,
                        value: s.noize,
                        hint: 'Reach for GFW when the default does not get through.',
                        onChanged: (v) => set((x) => x.noize = v),
                      ),
                      ChoiceRow(
                        label: 'IP version',
                        segmented: true,
                        options: Choices.ips,
                        value: s.ip,
                        onChanged: (v) => set((x) => x.ip = v),
                      ),
                      SwitchRow(
                        title: 'Fragment TLS ClientHello',
                        subtitle: 'Helps where a firewall resets the handshake',
                        value: s.fragment,
                        onChanged: (v) => set((x) => x.fragment = v),
                      ),
                      SwitchRow(
                        title: 'Quick reconnect',
                        subtitle: 'Reuse the last gateway that worked',
                        value: s.quickReconnect,
                        onChanged: (v) => set((x) => x.quickReconnect = v),
                      ),
                    ],
                  ),
                  if (c.backend.supportsVpn)
                    OxSection(
                      title: 'Android VPN',
                      children: [
                        SwitchRow(
                          title: 'Whole-device VPN',
                          subtitle: s.protocol == 'sstp' ? 'SSTP always uses the Android VPN service' : 'Off means proxy only',
                          value: s.protocol == 'sstp' || s.vpnMode,
                          enabled: s.protocol != 'sstp',
                          onChanged: (v) => set((x) => x.vpnMode = v),
                        ),
                        if (s.protocol != 'sstp') SwitchRow(
                          title: 'Fake DNS',
                          subtitle: 'Resolve names through the tunnel, no UDP needed',
                          value: s.fakeDns,
                          enabled: s.vpnMode,
                          onChanged: (v) => set((x) => x.fakeDns = v),
                        ),
                        if (s.protocol != 'sstp') SwitchRow(
                          title: 'Tunnel IPv6',
                          subtitle: 'Keeps IPv6 traffic from leaking around the VPN',
                          value: s.vpnIpv6,
                          enabled: s.vpnMode,
                          onChanged: (v) => set((x) => x.vpnIpv6 = v),
                        ),
                      ],
                    ),
                  OxSection(
                    title: 'Local proxy',
                    children: [
                      FieldRow(
                        label: 'SOCKS5 port',
                        value: '${s.socksPort}',
                        number: true,
                        onChanged: (v) => set((x) => x.socksPort = port(v, 1819)),
                      ),
                      SwitchRow(
                        title: 'HTTP proxy',
                        subtitle: 'Also serve an HTTP CONNECT proxy',
                        value: s.httpProxy,
                        onChanged: (v) => set((x) => x.httpProxy = v),
                      ),
                      if (s.httpProxy || (c.backend.supportsSystemProxy && s.systemProxy))
                        FieldRow(
                          label: 'HTTP port',
                          value: '${s.httpPort}',
                          number: true,
                          onChanged: (v) => set((x) => x.httpPort = port(v, 1820)),
                        ),
                      if (c.backend.supportsSystemProxy)
                        SwitchRow(
                          title: 'Windows system proxy',
                          subtitle: 'Set while connected, restored on disconnect',
                          value: s.systemProxy,
                          onChanged: (v) => set((x) => x.systemProxy = v),
                        ),
                      SwitchRow(
                        title: 'Share on local network',
                        subtitle: 'Listen on 0.0.0.0. No password: trusted networks only',
                        value: s.shareLan,
                        onChanged: (v) => set((x) => x.shareLan = v),
                      ),
                    ],
                  ),
                  OxSection(
                    title: 'Extra exit',
                    children: [
                      ChoiceRow(
                        options: {
                          for (final e in Choices.chains.entries)
                            if (e.key != 'psiphon' || c.backend.supportsPsiphon) e.key: e.value,
                        },
                        value: s.chain,
                        hint: Choices.chainHints[s.chain],
                        onChanged: (v) => set((x) => x.chain = v),
                      ),
                      if (s.chain == 'tor')
                        FieldRow(
                          label: 'Tor proxy port',
                          value: '${s.torPort}',
                          number: true,
                          onChanged: (v) => set((x) => x.torPort = port(v, 1822)),
                        ),
                      if (s.chain == 'psiphon' && c.backend.supportsPsiphon)
                        FieldRow(
                          label: 'Psiphon proxy port',
                          value: '${s.psiphonPort}',
                          number: true,
                          onChanged: (v) => set((x) => x.psiphonPort = port(v, 1821)),
                        ),
                    ],
                  ),
                  OxSection(
                    title: 'Advanced',
                    children: [
                      FieldRow(
                        label: 'Force peer (ip:port)',
                        hint: 'Skip the scan, e.g. 162.159.198.1:443',
                        value: s.peer,
                        mono: true,
                        onChanged: (v) => set((x) => x.peer = v),
                      ),
                      FieldRow(
                        label: 'DNS inside tunnel',
                        hint: '1.1.1.1,1.0.0.1',
                        value: s.dns,
                        mono: true,
                        onChanged: (v) => set((x) => x.dns = v),
                      ),
                      FieldRow(
                        label: 'Exit location',
                        hint: 'DE,SE allows only those · !IR blocks',
                        value: s.exitLoc,
                        onChanged: (v) => set((x) => x.exitLoc = v),
                      ),
                      FieldRow(
                        label: 'Extra core arguments',
                        hint: '--masque-sni www.cloudflare.com',
                        value: s.extraArgs,
                        mono: true,
                        onChanged: (v) => set((x) => x.extraArgs = v),
                      ),
                      SwitchRow(
                        title: 'Verbose logs',
                        subtitle: 'More detail in Activity, for troubleshooting',
                        value: s.verbose,
                        onChanged: (v) => set((x) => x.verbose = v),
                      ),
                    ],
                  ),
                  _About(platform: c.backend.platformLabel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Dirty extends StatelessWidget {
  const _Dirty({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final show = c.settingsDirty && c.isActive;
    return AnimatedSize(
      duration: Ox.medium,
      curve: Ox.easeOut,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: OxTile(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: Ox.warn, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Reconnect to use the new settings.', style: Ox.body(15))),
                    Pressable(
                      onTap: c.canToggle ? c.reconnect : null,
                      semanticLabel: 'Reconnect',
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Ox.blueCta, borderRadius: BorderRadius.circular(99)),
                        child: Text('Reconnect', style: Ox.body(14, weight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    return OxSection(
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Row(
            children: [
              const OxLogoTile(size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const OxWordmark(size: 22),
                    const SizedBox(height: 4),
                    Text('Version $kAppVersion · $platform', style: Ox.body(14, color: Ox.secondary)),
                    const SizedBox(height: 2),
                    Text('Created by $kCreator', style: Ox.body(14, color: Ox.text, weight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
