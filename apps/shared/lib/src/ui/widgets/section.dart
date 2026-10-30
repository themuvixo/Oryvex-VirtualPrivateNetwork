import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// A page's big title, apple.com style: a small blue eyebrow over a large tight headline.
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.title, this.eyebrow, this.trailing});

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final big = context.oxSize != OxSize.compact;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(eyebrow!, style: Ox.eyebrow())),
                Text(title, style: Ox.headline(big ? 48 : 38)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A rounded white tile on the grey canvas: apple.com's product tile.
class OxTile extends StatelessWidget {
  const OxTile({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? Ox.tile;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(Ox.radiusTile),
        boxShadow: tileColor == Ox.tile ? Ox.tileShadow : null,
      ),
      child: child,
    );
  }
}

/// An inset group of rows with a heading and an optional footnote, like iOS Settings.
/// Rows are separated by hairlines that start where the text starts.
class OxSection extends StatelessWidget {
  const OxSection({super.key, required this.title, required this.children, this.trailing, this.footer});

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Divider(height: 0.6, thickness: 0.6, color: Ox.hairlineSoft),
        ));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Ox.headline(20, weight: FontWeight.w600))),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ox.radiusGroup),
              boxShadow: Ox.tileShadow,
            ),
            child: ClipRRect(
            borderRadius: BorderRadius.circular(Ox.radiusGroup),
            child: ColoredBox(
              color: Ox.tile,
              child: AnimatedSize(
                duration: Ox.medium,
                curve: Ox.easeOut,
                alignment: Alignment.topCenter,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
              ),
            ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(footer!, style: Ox.body(13, color: Ox.secondary)),
            ),
        ],
      ),
    );
  }
}

/// Padding every row in an [OxSection] shares.
const _rowPad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);

/// A labelled block inside a section: a label, a control, and an optional hint below it.
class OxBlock extends StatelessWidget {
  const OxBlock({super.key, this.label, required this.child, this.hint});

  final String? label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _rowPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(label!, style: Ox.body(15, weight: FontWeight.w500)),
            ),
          child,
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AnimatedSwitcher(
                duration: Ox.medium,
                switchInCurve: Ox.easeOut,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(hint!, key: ValueKey<String>(hint!), style: Ox.body(14, color: Ox.secondary)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Apple's segmented control: a sliding thumb under the chosen label.
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList(growable: false);
    final index = keys.indexOf(value).clamp(0, keys.length - 1);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 360.0;
        final seg = (width - 6) / keys.length;
        return Container(
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Ox.field, borderRadius: BorderRadius.circular(11)),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: context.reduceMotion ? Duration.zero : Ox.medium,
                curve: Ox.easeOut,
                left: seg * index,
                top: 0,
                bottom: 0,
                width: seg,
                child: Container(
                  decoration: BoxDecoration(
                    color: Ox.tileTop,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < keys.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: i == index,
                        button: true,
                        label: options[keys[i]],
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(keys[i]),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimatedDefaultTextStyle(
                                    duration: Ox.fast,
                                    style: Ox.body(14,
                                        weight: i == index ? FontWeight.w600 : FontWeight.w500,
                                        color: i == index ? Ox.text : Ox.secondary),
                                    child: Text(options[keys[i]]!, maxLines: 1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A wrap of single-choice pills bound to a string value.
class ChoicePills extends StatelessWidget {
  const ChoicePills({super.key, required this.options, required this.value, required this.onChanged});

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          Pressable(
            onTap: () => onChanged(e.key),
            semanticLabel: e.value,
            borderRadius: BorderRadius.circular(99),
            child: AnimatedContainer(
              duration: Ox.medium,
              curve: Ox.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: e.key == value ? Ox.blueCta : Ox.field,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: e.key == value ? Ox.blueCta : Ox.hairlineSoft),
              ),
              child: AnimatedDefaultTextStyle(
                duration: Ox.fast,
                style: Ox.body(14,
                    weight: e.key == value ? FontWeight.w600 : FontWeight.w500,
                    color: e.key == value ? Colors.white : Ox.text),
                child: Text(e.value),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kept for code that still asks for a labelled choice: pills under a label, hint below.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.segmented = false,
  });

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final bool segmented;

  @override
  Widget build(BuildContext context) {
    return OxBlock(
      label: label,
      hint: hint,
      child: segmented
          ? Segmented(options: options, value: value, onChanged: onChanged)
          : ChoicePills(options: options, value: value, onChanged: onChanged),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: AnimatedOpacity(
                  duration: Ox.fast,
                  opacity: enabled ? 1 : 0.45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Ox.body(16, weight: FontWeight.w500)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: Ox.body(14, color: Ox.secondary)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Switch(value: value, onChanged: enabled ? onChanged : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row that opens something: label, optional value, chevron.
class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.title, this.value, this.onTap, this.icon});

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: _rowPad,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: Ox.blue),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(title, style: Ox.body(16, weight: FontWeight.w500))),
            if (value != null) Text(value!, style: Ox.body(15, color: Ox.secondary)),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: Ox.tertiary, size: 22),
            ],
          ],
        ),
      ),
    );
  }
}

/// A text field that commits on every change but keeps its own controller across rebuilds.
class FieldRow extends StatefulWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.number = false,
    this.mono = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool number;
  final bool mono;
  final ValueChanged<String> onChanged;

  @override
  State<FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<FieldRow> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: TextField(
        controller: _c,
        keyboardType: widget.number ? TextInputType.number : TextInputType.text,
        autocorrect: false,
        enableSuggestions: false,
        style: widget.mono || widget.number ? Ox.code(15) : Ox.body(16),
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onChanged: widget.onChanged,
      ),
    );
  }
}
