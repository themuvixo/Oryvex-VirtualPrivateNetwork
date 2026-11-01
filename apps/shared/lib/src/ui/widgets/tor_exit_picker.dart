import 'package:flutter/material.dart';

import '../../core/controller.dart';
import '../../core/settings.dart';
import '../../core/tor_exits.dart';
import '../theme.dart';
import 'motion.dart';
import 'section.dart';

/// "Auto exit", "Fastest exit", "Exit in Germany": what the Tor route is set to leave from.
String torExitLabel(CoreController c) {
  final exit = c.settings.torExit;
  return switch (exit) {
    'auto' => 'auto exit',
    'fastest' => 'fastest exit',
    _ => 'exit in ${c.torExits.nameOf(exit)}',
  };
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// "74 countries · 1,312 exit relays · updated 2 h ago" or the bundled-list note.
String torDirectoryNote(TorExitDirectory dir) {
  if (dir.isBundled || dir.updated == null) {
    return '${dir.countries.length} long-standing exit countries, bundled. The live list is '
        'fetched through Tor itself the first time you connect.';
  }
  return '${dir.countries.length} countries · ${dir.totalRelays} exit relays · '
      'from the Tor directory, updated ${_ago(dir.updated!)}';
}

/// Where Tor leaves from: Auto, Fastest, or a country. Country shows the best-served countries
/// as tiles (two or three across, by width) and every other one in a list below.
class TorExitPicker extends StatelessWidget {
  const TorExitPicker({super.key, required this.controller, this.quickCount = 9});

  final CoreController controller;

  /// How many countries get a tile of their own before the full list.
  final int quickCount;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final dir = c.torExits;
    final mode = Choices.torExitMode(s.torExit);

    void pickMode(String v) {
      c.updateSettings((x) {
        if (v != 'country') {
          x.torExit = v;
        } else if (Choices.torExitMode(x.torExit) != 'country') {
          x.torExit = dir.countries.isEmpty ? 'de' : dir.countries.first.code;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Tor exit', style: Ox.body(15, weight: FontWeight.w500))),
            _InUse(controller: c),
          ],
        ),
        const SizedBox(height: 10),
        Segmented(options: Choices.torExitModes, value: mode, onChanged: pickMode),
        const SizedBox(height: 10),
        Text(Choices.torExitHints[mode] ?? '', style: Ox.body(14, color: Ox.secondary)),
        AnimatedSize(
          duration: Ox.medium,
          curve: Ox.easeOut,
          alignment: Alignment.topCenter,
          child: mode != 'country'
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _Countries(controller: c, quickCount: quickCount),
                ),
        ),
        const SizedBox(height: 12),
        Text(torDirectoryNote(dir), style: Ox.body(13, color: Ox.tertiary)),
      ],
    );
  }
}

/// The exit the running proxy settled on, as a small capsule. Nothing while disconnected.
class _InUse extends StatelessWidget {
  const _InUse({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final exit = c.torExitInUse;
    final String? text;
    if (exit == null) {
      text = c.isActive ? 'Choosing…' : null;
    } else if (exit == 'auto') {
      text = 'In use: Tor\'s pick';
    } else {
      text = 'In use: ${exit.toUpperCase()}${c.torExitMs == null ? '' : ' · ${c.torExitMs} ms'}';
    }
    return AnimatedSwitcher(
      duration: Ox.medium,
      child: text == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Container(
              key: ValueKey<String>(text),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ox.blue.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(text, style: Ox.body(13, weight: FontWeight.w600, color: Ox.blueSoft)),
            ),
    );
  }
}

class _Countries extends StatelessWidget {
  const _Countries({required this.controller, required this.quickCount});

  final CoreController controller;
  final int quickCount;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chosen = c.settings.torExit;
    final all = c.torExits.countries;
    final quick = all.take(quickCount).toList();
    final inQuick = quick.any((x) => x.code == chosen);

    void pick(String code) => c.updateSettings((x) => x.torExit = code);

    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final cols = box.maxWidth >= 600 ? 3 : (box.maxWidth >= 300 ? 2 : 1);
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final x in quick)
                  SizedBox(
                    width: w,
                    child: _CountryTile(country: x, selected: x.code == chosen, onTap: () => pick(x.code)),
                  ),
              ],
            ),
            if (all.length > quick.length) ...[
              const SizedBox(height: 10),
              _AllCountries(
                countries: all,
                value: inQuick ? null : (all.any((x) => x.code == chosen) ? chosen : null),
                onChanged: pick,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A two-letter badge: flag emoji do not render on Windows, letters always do.
class CountryCodeBadge extends StatelessWidget {
  const CountryCodeBadge({super.key, required this.code, this.selected = false, this.size = 34});

  final String code;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Ox.medium,
      curve: Ox.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Ox.blueCta : Ox.tileHi,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        code.toUpperCase(),
        style: Ox.code(size * 0.38, weight: FontWeight.w700, height: 1.0, color: selected ? Colors.white : Ox.text),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({required this.country, required this.selected, required this.onTap});

  final TorExitCountry country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = country.detail;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      semanticLabel: 'Leave Tor from ${country.name}',
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: Ox.medium,
        curve: Ox.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? Ox.blue.withValues(alpha: 0.12) : Ox.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Ox.blueCta : Ox.hairlineSoft, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            CountryCodeBadge(code: country.code, selected: selected),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(14, weight: FontWeight.w600)),
                  if (detail.isNotEmpty)
                    Text(detail,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(12.5, color: Ox.secondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllCountries extends StatelessWidget {
  const _AllCountries({required this.countries, required this.value, required this.onChanged});

  final List<TorExitCountry> countries;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = List<TorExitCountry>.of(countries)..sort((a, b) => a.name.compareTo(b.name));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Ox.field, borderRadius: BorderRadius.circular(Ox.radiusField)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          menuMaxHeight: 420,
          dropdownColor: Ox.tile,
          borderRadius: BorderRadius.circular(14),
          hint: Text('All ${countries.length} countries…', style: Ox.body(15, color: Ox.secondary)),
          icon: Icon(Icons.expand_more_rounded, color: Ox.secondary),
          items: [
            for (final x in sorted)
              DropdownMenuItem<String>(
                value: x.code,
                child: Row(
                  children: [
                    CountryCodeBadge(code: x.code, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        x.detail.isEmpty ? x.name : '${x.name}  ·  ${x.detail}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ox.body(15),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
