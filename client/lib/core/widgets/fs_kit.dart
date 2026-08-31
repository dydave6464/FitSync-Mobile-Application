import 'package:flutter/material.dart';

import '../theme.dart';

/// The FitSync component kit, mirroring the prototype's `kit.jsx` and the
/// `.btn` / `.card` / `.chip` / `.field` rules in `styles.css`.
///
/// Screens compose these instead of styling Material widgets inline, which is
/// what keeps the look consistent and the screens readable.

enum FsButtonKind { primary, secondary, ghost }

/// `.btn` — 52px, full-pill, 15/700. The primary variant carries the accent
/// glow (`box-shadow: 0 10px 24px -10px`).
class FsButton extends StatelessWidget {
  const FsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = FsButtonKind.primary,
    this.icon,
    this.busy = false,
    this.small = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final FsButtonKind kind;
  final Widget? icon;
  final bool busy;
  final bool small;

  /// Sign out is a ghost button in red.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final enabled = onPressed != null && !busy;
    final height = small ? 42.0 : 52.0;

    final (Color bg, Color fg, Color border) = switch (kind) {
      FsButtonKind.primary => (t.accent, t.onAccent, Colors.transparent),
      FsButtonKind.secondary => (t.surface, t.text, t.line2),
      FsButtonKind.ghost =>
        (Colors.transparent, danger ? t.red : t.text2, Colors.transparent),
    };

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FsRadius.pill),
          boxShadow: kind == FsButtonKind.primary && enabled
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                    spreadRadius: -10,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FsRadius.pill),
            side: BorderSide(color: border),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(FsRadius.pill),
            child: SizedBox(
              height: height,
              child: Center(
                child: busy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kind == FsButtonKind.primary ? fg : t.accent,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            IconTheme(
                              data: IconThemeData(color: fg, size: 18),
                              child: icon!,
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Flexible so the label shrinks to an ellipsis
                          // instead of overflowing the row at large
                          // accessibility text scales on narrow screens —
                          // the same remedy already used for FsChip and the
                          // eyebrow row. maxLines: 1 rather than letting it
                          // wrap, as FsNav does, because this Row sits in a
                          // fixed-height button and a second line would
                          // overflow that instead.
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: small ? 13.5 : 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.15,
                                color: fg,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.card` — surface, hairline border, 22px radius. `accent` is the
/// `.accent-card` gradient used for a selected option.
class FsCard extends StatelessWidget {
  const FsCard({
    super.key,
    required this.child,
    this.accent = false,
    this.small = false,
    this.onTap,
    this.padding,
  });

  final Widget child;
  final bool accent;
  final bool small;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final radius = BorderRadius.circular(small ? FsRadius.md : FsRadius.card);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: accent ? t.accentLine : t.line),
        color: accent ? null : t.surface,
        gradient: accent
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.accent.withValues(alpha: 0.16),
                  t.accent.withValues(alpha: 0.03),
                ],
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: padding ?? EdgeInsets.all(small ? 13 : 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// `.chip` — pill, surface-2 when off, solid accent when on.
class FsChip extends StatelessWidget {
  const FsChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.small = false,
    this.showCheck = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  /// The equipment chips carry a check when on, as the design shows. The
  /// location chips do not — they are single-select, so a tick would read as
  /// a second affordance.
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Material(
      color: selected ? t.accent : t.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FsRadius.pill),
        side: BorderSide(color: selected ? Colors.transparent : t.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FsRadius.pill),
        child: Padding(
          padding: small
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
              : const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The slot is reserved whenever the chip can show a check, not
              // only while it does. Building it on selection alone made the
              // chip 18px wider the moment it was ticked, which reflowed the
              // enclosing Wrap and shunted its neighbours onto another line.
              if (showCheck) ...[
                SizedBox(
                  width: small ? 11 : 13,
                  height: small ? 11 : 13,
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: small ? 11 : 13,
                          color: t.onAccent,
                        )
                      : null,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: small ? 11 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? t.onAccent : t.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.field` — 52px, 16px radius, surface, accent border on focus.
class FsField extends StatelessWidget {
  const FsField({
    super.key,
    required this.controller,
    required this.hint,
    this.fieldKey,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.suffix,
  });

  /// Applied to the inner [TextField] rather than to this wrapper, so
  /// `tester.enterText` can find the editable it needs.
  final Key? fieldKey;

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      autocorrect: false,
      style: TextStyle(fontSize: 14, color: t.text),
      cursorColor: t.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: t.text3),
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: t.text3),
        suffixText: suffix,
        suffixStyle: TextStyle(fontSize: 13, color: t.text3),
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FsRadius.md),
          borderSide: BorderSide(color: t.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FsRadius.md),
          borderSide: BorderSide(color: t.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FsRadius.md),
          borderSide: BorderSide(color: t.accentLine),
        ),
      ),
    );
  }
}

/// `.eyebrow` — the mono, uppercase, wide-tracked section label.
class FsEyebrow extends StatelessWidget {
  const FsEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: fsEyebrow(context.fs));
}

/// `.tag` — the small count pill the design puts opposite a section eyebrow.
class FsTag extends StatelessWidget {
  const FsTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(FsRadius.pill),
        border: Border.all(color: t.line),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: t.text2,
        ),
      ),
    );
  }
}

/// One destination in [FsNav].
class FsNavItem {
  const FsNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// `.botnav` — the bottom bar. Stateless on purpose: it reports a tap and
/// renders the index it is given, so the shell owns which tab is current.
class FsNav extends StatelessWidget {
  const FsNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<FsNavItem> items;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final (index, item) in items.indexed)
                Expanded(
                  child: InkWell(
                    key: Key('nav.$index'),
                    onTap: () => onSelect(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          size: 21,
                          color: index == currentIndex ? t.accent : t.text3,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: index == currentIndex ? t.accent : t.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The onboarding progress strip: one bar per step, filled up to [step].
/// The prototype uses discrete segments rather than a continuous bar.
class FsStepBars extends StatelessWidget {
  const FsStepBars({super.key, required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < step ? t.accent : t.surface2,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The circular tick on a selected option card.
class FsRadioDot extends StatelessWidget {
  const FsRadioDot({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : Colors.transparent,
        border: Border.all(color: selected ? t.accent : t.line2, width: 2),
      ),
      child: selected ? Icon(Icons.check, size: 13, color: t.onAccent) : null,
    );
  }
}

/// The square icon tile used down the left of option rows and settings rows.
class FsIconTile extends StatelessWidget {
  const FsIconTile({
    super.key,
    required this.icon,
    this.selected = false,
    this.size = 38,
    this.color,
  });

  final IconData icon;
  final bool selected;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? t.accent : t.surface2,
        borderRadius: BorderRadius.circular(FsRadius.sm),
        border: Border.all(color: selected ? Colors.transparent : t.line),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: selected ? t.onAccent : (color ?? t.text2),
      ),
    );
  }
}
