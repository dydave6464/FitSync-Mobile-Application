import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../units.dart';

/// The FitSync component kit, mirroring the prototype's `kit.jsx` and the
/// `.btn` / `.card` / `.chip` / `.field` rules in `styles.css`.
///
/// Screens compose these instead of styling Material widgets inline, which is
/// what keeps the look consistent and the screens readable.

/// `box-shadow: 0 10px 24px -10px` in the accent — the glow the design puts
/// under anything raised and accent-coloured. `.btn.primary` and the nav's
/// centre fab both carry it in `styles.css`; one list here is what stops the
/// two drifting apart.
List<BoxShadow> fsAccentGlow(FsTokens t) => [
  BoxShadow(
    color: t.accent.withValues(alpha: 0.45),
    blurRadius: 24,
    offset: const Offset(0, 10),
    spreadRadius: -10,
  ),
];

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
    this.wrapLabel = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final FsButtonKind kind;
  final Widget? icon;
  final bool busy;
  final bool small;

  /// Sign out is a ghost button in red.
  final bool danger;

  /// Lets a label too long for one line wrap, the button growing to fit,
  /// instead of ending in an ellipsis. For choices that must be read whole
  /// at large text sizes -- a dialog's "Discard it & start new" cut to
  /// "Discard it &…" hides what the tap does. Off by default, so every other
  /// button keeps its fixed height.
  final bool wrapLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final enabled = onPressed != null && !busy;
    final height = small ? 42.0 : 52.0;

    final (Color bg, Color fg, Color border) = switch (kind) {
      FsButtonKind.primary => (t.accent, t.onAccent, Colors.transparent),
      FsButtonKind.secondary => (t.surface, t.text, t.line2),
      FsButtonKind.ghost => (
        Colors.transparent,
        danger ? t.red : t.text2,
        Colors.transparent,
      ),
    };

    // One node that says "button", whether it can be pressed, and its label.
    // While busy the label is replaced on screen by a spinner, so the node
    // carries it instead, with "loading" so the wait is announced too.
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: busy ? '$label, loading' : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FsRadius.pill),
            boxShadow: kind == FsButtonKind.primary && enabled
                ? fsAccentGlow(t)
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
              child: ConstrainedBox(
                constraints: wrapLabel
                    ? BoxConstraints(minHeight: height)
                    : BoxConstraints.tightFor(height: height),
                // Horizontal room for the label. Invisible on a full-width
                // button -- Center already had all the space it needed -- but
                // without it a button sized to its own content shrink-wraps to
                // the bare word and the pill radius cuts into it.
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: small ? 16 : 20,
                    // Only a wrapped label can reach the edges top and bottom.
                    vertical: wrapLabel ? 10 : 0,
                  ),
                  child: Center(
                    // A wrapped button has only a minimum height, which a
                    // plain Center would stretch to fill whatever its parent
                    // allows. Hug the label instead.
                    heightFactor: wrapLabel ? 1 : null,
                    child: busy
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kind == FsButtonKind.primary
                                  ? fg
                                  : t.accent,
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
                              // the same remedy already used for FsNav and the
                              // eyebrow row. maxLines: 1 rather than letting it
                              // wrap, as FsChip does, because this Row sits in a
                              // fixed-height button and a second line would
                              // overflow that instead -- unless [wrapLabel]
                              // lets the button grow with it.
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: wrapLabel ? null : 1,
                                  overflow: wrapLabel
                                      ? null
                                      : TextOverflow.ellipsis,
                                  // Centred lines only when there can be more
                                  // than one; every other button draws as it
                                  // always has.
                                  textAlign: wrapLabel
                                      ? TextAlign.center
                                      : null,
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
    this.selected,
  });

  final Widget child;
  final bool accent;
  final bool small;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Whether this card is a chosen option, for screen readers. Null for a
  /// card that is not one of a set of choices. Kept apart from [accent],
  /// which is also used for emphasis on cards nobody selects.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final radius = BorderRadius.circular(small ? FsRadius.md : FsRadius.card);

    final card = DecoratedBox(
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

    // A card that only displays something stays out of the semantics tree's
    // way, so its contents read as they always have. A tappable or
    // selectable one becomes a single node that says what it is.
    if (onTap == null && selected == null) return card;
    return Semantics(
      container: true,
      button: onTap != null,
      selected: selected,
      child: card,
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

  /// Null leaves the chip inert and announced as disabled.
  final VoidCallback? onTap;
  final bool small;

  /// The equipment chips carry a check when on, as the design shows. The
  /// location chips do not — they are single-select, so a tick would read as
  /// a second affordance.
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    // Drawn about 30 dp tall; answers a thumb across 48 wherever its parent
    // has that room. A one-row Wrap or Row is only as tall as the chip, so a
    // row of them sits in an [FsTapRoom] for the band to reach past it.
    return _TapReach(
      button: true,
      enabled: onTap != null,
      selected: selected,
      child: Material(
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
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.maxLines = 1,
    this.inputFormatters,
    this.autofillHints,
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

  /// A widget inside the field's own border, at its trailing edge -- a clear
  /// button, a reveal toggle. Distinct from [suffix], which is a unit ('kg')
  /// and cannot be tapped. Placing an affordance beside the field instead
  /// leaves it outside the box it acts on, and outside the tap target the
  /// border implies.
  final Widget? trailing;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  /// Lines the box may grow to before it scrolls. One, as every field in the
  /// app has been, until something needs to hold a sentence: typed into a
  /// single line, a sentence scrolls sideways and hides its own beginning.
  final int maxLines;

  /// Restrictions on what can be typed or pasted, e.g. digits only.
  final List<TextInputFormatter>? inputFormatters;

  /// What the platform may offer to fill in, e.g. a one-time code from Mail.
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      autocorrect: false,
      style: TextStyle(fontSize: 14, color: t.text),
      cursorColor: t.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: t.text3),
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: t.text3),
        suffixText: suffix,
        suffixStyle: TextStyle(fontSize: 13, color: t.text3),
        suffixIcon: trailing,
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 16,
        ),
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

/// `.seg` — the pill track whose selected segment is filled with accent.
///
/// Single-select and always visible, unlike a [Wrap] of [FsChip]s: the design
/// uses it where the choices are two sides of one question (sex, experience)
/// rather than a set the user picks through.
class FsSegmented extends StatelessWidget {
  const FsSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<({String value, String label})> options;

  /// The enum value that is on, or null. A value matching no option — a
  /// profile saved under a choice since withdrawn — simply lights nothing.
  final String? selected;

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FsRadius.pill),
        side: BorderSide(color: t.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final (index, option) in options.indexed) ...[
              if (option != options.first) const SizedBox(width: 2),
              Expanded(
                // Each segment is its own button in a single-choice group,
                // with its place in the set, so a screen reader can say
                // "Female, selected, 2 of 2" rather than just the word.
                child: Semantics(
                  container: true,
                  button: true,
                  enabled: true,
                  selected: selected == option.value,
                  inMutuallyExclusiveGroup: true,
                  hint: '${index + 1} of ${options.length}',
                  child: InkWell(
                    key: Key('segment.${option.value}'),
                    onTap: () => onSelected(option.value),
                    borderRadius: BorderRadius.circular(FsRadius.pill),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected == option.value
                            ? t.accent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(FsRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          option.label,
                          textAlign: TextAlign.center,
                          // A label that fits in one line renders at exactly
                          // that height (unchanged from before); one that
                          // doesn't wraps to a second line rather than
                          // ellipsizing — "New to training" at 320dp is the
                          // case this guards, and a label is a binding
                          // constraint that must never be shortened.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: selected == option.value
                                ? t.onAccent
                                : t.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Three whole digits and at most one decimal place.
///
/// No height in centimetres, weight or goal weight in kilograms needs a fourth
/// digit, and refusing the keystroke is quieter than taking 1750 and failing
/// validation after the step is submitted. The decimal survives because half a
/// kilogram is a real measurement — the cap is about absurd values, not
/// precision.
final _measurement = RegExp(r'^\d{0,3}(\.\d?)?$');

/// The design's measurement card: a dim label over a big mono number.
///
/// The number is the input rather than a rendering of one — the mockup is
/// static, but the step this appears on has to collect these — so the card
/// reads as designed and still types.
class FsStatField extends StatelessWidget {
  const FsStatField({
    super.key,
    required this.label,
    required this.unit,
    required this.controller,
    this.fieldKey,
    this.accent = false,
    this.unitControl,
  });

  final String label;
  final String unit;

  /// Replaces the static [unit] label. The unit belongs next to the number it
  /// describes, so a field whose unit the user chooses puts the control right
  /// there rather than somewhere else on the step.
  final Widget? unitControl;
  final TextEditingController controller;

  /// Applied to the inner [TextField], so `tester.enterText` finds an
  /// editable rather than this wrapper.
  final Key? fieldKey;

  /// Accent border and accent digits, which the design gives goal weight.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FsRadius.sm),
        border: Border.all(color: accent ? t.accentLine : t.line),
      ),
      // The card's 14 dp of padding past the switch is the rest of lb's band;
      // it lies outside the Column, so the room is taken here.
      child: FsTapRoom(
        reach: 0,
        endReach: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FsEyebrow(label),
            // The room above the row is the label's, which takes no taps, so
            // a thumb landing just over the switch still finds it.
            FsTapRoom(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: TextField(
                      key: fieldKey,
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (previous, next) => _measurement.hasMatch(next.text)
                              ? next
                              : previous,
                        ),
                      ],
                      style: TextStyle(
                        fontFamily: fsMonoFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.22,
                        color: accent ? t.accentText : t.text,
                      ),
                      cursorColor: t.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: '--',
                        hintStyle: TextStyle(
                          fontFamily: fsMonoFamily,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: t.text3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (unitControl case final control?)
                    _NoReachBack(child: control)
                  else
                    Text(unit, style: TextStyle(fontSize: 11, color: t.text3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps [child]'s tap band from reaching back over the sibling before it.
///
/// A Row asks its last child first, so a control's band grown to the left
/// would take the right-hand end of the field beside it: in a stat card a
/// tap meant for the number would flip the unit. Above, below and past its
/// far end the band answers as before. The cost is that the near unit, kg,
/// falls short of 48 dp wide: the number sits right beside it.
class _NoReachBack extends SingleChildRenderObjectWidget {
  const _NoReachBack({required Widget super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderNoReachBack();
}

class _RenderNoReachBack extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Not the usual check against this box: the child's band lies outside
    // it, and only the side facing the field is closed.
    if (position.dx < 0 || !hitTestChildren(result, position: position)) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// `.eyebrow` — the mono, uppercase, wide-tracked section label.
class FsEyebrow extends StatelessWidget {
  const FsEyebrow(this.text, {super.key, this.maxLines = 1});

  final String text;

  /// One line by default, as the design draws it; more where the line says
  /// something a reader needs and there is room to grow.
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: fsEyebrow(context.fs),
  );
}

/// One line of [text] that shrinks to fit rather than wraps: a figure or a
/// one-word label in a narrow tile, which at large text would otherwise break
/// mid-word ("6," "42" "0"). Never soft-wrapped, so the height it reports to
/// a row sizing tiles to the tallest is one line's -- the line's full size,
/// though, not its shrunk one, so a shrunk tile keeps a little space below.
class FsOneLine extends StatelessWidget {
  const FsOneLine(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(text, style: style, maxLines: 1, softWrap: false),
  );
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
    this.onFabTap,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<FsNavItem> items;

  /// Opens the start-workout sheet. Null on any bar that has no fab.
  ///
  /// Deliberately NOT an [FsNavItem]: the fab selects nothing, has no label
  /// and no active state, and adding it to `items` would shift Nutrition from 2
  /// to 3 and Profile from 3 to 4 — renumbering every `nav.$index` key the
  /// shell's tests tap.
  final VoidCallback? onFabTap;

  static const double _barHeight = 58;

  /// The diameter the prototype gives the circle.
  static const double _fabSize = 50;

  /// A tab cell's own stack: icon over label.
  static const double _tabIconSize = 21;
  static const double _tabGap = 3;

  /// The fab's footprint in the [Row]: wider than the circle, so the tab
  /// cells either side of it keep their gap.
  static const double _fabSlotWidth = 62;

  @override
  Widget build(BuildContext context) => _bar(context.fs);

  Widget _bar(FsTokens t) => Container(
    decoration: BoxDecoration(
      color: t.surface,
      border: Border(top: BorderSide(color: t.line)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: _barHeight,
        child: Row(
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index == 2 && onFabTap != null)
                SizedBox(
                  width: _fabSlotWidth,
                  child: Center(child: _fab(t)),
                ),
              Expanded(
                child: InkWell(
                  key: Key('nav.$index'),
                  onTap: () => onSelect(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: _tabIconSize,
                        color: index == currentIndex ? t.accentText : t.text3,
                      ),
                      const SizedBox(height: _tabGap),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: index == currentIndex ? t.accentText : t.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  /// The centre circle.
  ///
  /// A plain child of the tab [Row], which is what puts it level with the
  /// tabs: the row centres every child on its cross axis, so a 50px circle in
  /// a 58px row lands on the same centreline as an icon-over-label cell with
  /// no arithmetic to drift. It also means the whole circle is inside the
  /// bar's own box, so all of it is hit-testable — the property a raised cap
  /// had to be positioned carefully to keep, and a `Transform.translate`
  /// would have lost outright.
  Widget _fab(FsTokens t) => DecoratedBox(
    // Circle, not the default rectangle: the glow has to follow the
    // shape it falls from. Painted outside the Material rather than
    // through its `elevation`, so it is the design's accent glow and
    // not Material's own grey ambient shadow.
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: fsAccentGlow(t),
    ),
    child: Material(
      color: t.accent,
      shape: const CircleBorder(),
      child: InkWell(
        key: const Key('nav.fab'),
        customBorder: const CircleBorder(),
        onTap: onFabTap,
        child: SizedBox(
          width: _fabSize,
          height: _fabSize,
          child: Icon(Icons.add, size: 26, color: t.onAccent),
        ),
      ),
    ),
  );
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

/// The prototype's progress ring (`kit.jsx` Ring), with [child] centred.
///
/// Indeterminate on purpose. The prototype draws a determinate arc at 72%,
/// but the server builds a plan in a single call and reports no progress, so
/// a filled fraction would be a number we invented.
class FsRing extends StatelessWidget {
  const FsRing({super.key, this.size = 120, this.stroke = 10, this.child});

  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: stroke,
              color: t.accent,
              backgroundColor: t.surface2,
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

/// A compact kg / lb switch, sized to sit inside a table's column header.
///
/// It lives on the header of the column it governs rather than off in a
/// settings screen, because that is where the number it describes is. The
/// weight field's hint was the only place the unit ever appeared, and a hint
/// disappears the moment a value is typed.
class FsUnitToggle extends StatelessWidget {
  const FsUnitToggle({super.key, required this.value, this.onChanged});

  final WeightUnit value;

  /// Null renders the toggle inert rather than absent, so a host with nowhere
  /// to write the change still says which unit is in force.
  final ValueChanged<WeightUnit>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    // The band for taps is the whole switch's, 48 dp tall: one around each
    // unit alone could not reach past this row's own few pixels of height.
    // A tap above or below a unit is that unit; one off either end is the
    // unit at that end, as far as the parent has room for it. At the end of
    // a row that room is the parent's own, so the row goes in an [FsTapRoom]
    // with an endReach. Wide enough for two 48 dp targets and the slash
    // between them, with room for the slash to grow at large text.
    return _TapReach(
      minSize: const Size(2 * _minTapTarget + 16, _minTapTarget),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final unit in WeightUnit.values) ...[
            if (unit != WeightUnit.values.first)
              Text('/', style: fsEyebrow(t).copyWith(letterSpacing: 0)),
            _TapReach(
              // What a screen reader frames: each unit at full size, grown
              // outward, away from the other, so the two never overlap.
              anchor: unit == WeightUnit.values.first
                  ? Alignment.centerRight
                  : unit == WeightUnit.values.last
                  ? Alignment.centerLeft
                  : Alignment.center,
              button: onChanged == null || unit == value ? null : true,
              selected: unit == value,
              child: InkWell(
                key: Key('unit.${unit.api}'),
                // The unit already in force is not a destination, so it takes
                // no tap -- and reads as the label it also is.
                onTap: onChanged == null || unit == value
                    ? null
                    : () => onChanged!(unit),
                borderRadius: BorderRadius.circular(FsRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    unit.api.toUpperCase(),
                    style: fsEyebrow(
                      t,
                    ).copyWith(color: unit == value ? t.accentText : t.text3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The smallest target a thumb should be asked to hit.
const double _minTapTarget = 48;

/// Lets [child] answer taps in a band around itself, 48 dp on each short
/// axis unless told otherwise, without taking up that room. The control is
/// drawn and laid out exactly as before, so a Wrap of chips keeps its
/// spacing, and a thumb that lands just off the pill still counts. A tap in
/// the band is moved onto the control's middle line, inside its ends, where
/// any rounded shape it is drawn in still holds it -- as Material moves one
/// on its own padded targets.
///
/// The band reaches only as far as the parent's own box: a tap outside that
/// never gets here. It is the full 48 dp only where no other chip's band
/// overlaps it; a gap shared with another chip is split at its middle, as
/// below. At a Wrap's or Row's outer edge the parent cuts it off,
/// which in a single row is the whole band above and below. Such a row goes
/// in an [FsTapRoom], or gives each chip a sized box of its own, as the
/// check-in and the library's muscle buttons do.
///
/// Beside another chip in the same parent, the band gives way: a point on
/// that chip's pill stays that chip's, and a gap between two chips splits
/// at its middle, so neither row of a Wrap takes the other's edge. Any other
/// tappable box is not so lucky: a parent hit-tests its last child first, so
/// the band takes over the edge of an earlier sibling it overlaps -- a button
/// directly above a chip loses its bottom few dp to the chip. Let it sit
/// beside gaps, text or other chips only. The give-way works between direct
/// siblings, so a chip wrapped in its own Padding or Tooltip is not seen by
/// its neighbours.
///
/// Given any of [button], [enabled] or [selected], it also carries the
/// control's semantics, so a screen reader frames the band rather than the
/// pill: a node's rect is its owner's.
class _TapReach extends SingleChildRenderObjectWidget {
  const _TapReach({
    required Widget super.child,
    this.minSize = const Size.square(_minTapTarget),
    this.anchor = Alignment.center,
    this.button,
    this.enabled,
    this.selected,
  });

  /// The band's size, where the control is smaller.
  final Size minSize;

  /// Where the control sits in its band. Centred grows the band evenly; at
  /// an edge, it grows only away from that edge.
  final Alignment anchor;

  final bool? button;
  final bool? enabled;
  final bool? selected;

  @override
  _RenderTapReach createRenderObject(BuildContext context) => _RenderTapReach(
    minSize: minSize,
    anchor: anchor,
    button: button,
    enabled: enabled,
    selected: selected,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTapReach renderObject) {
    renderObject
      ..minSize = minSize
      ..anchor = anchor
      ..button = button
      ..enabled = enabled
      ..selected = selected;
  }
}

class _RenderTapReach extends RenderProxyBox {
  _RenderTapReach({
    required this._minSize,
    required this._anchor,
    this._button,
    this._enabled,
    this._selected,
  });

  Size _minSize;
  set minSize(Size value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsSemanticsUpdate();
  }

  Alignment _anchor;
  set anchor(Alignment value) {
    if (value == _anchor) return;
    _anchor = value;
    markNeedsSemanticsUpdate();
  }

  bool? _button;
  set button(bool? value) {
    if (value == _button) return;
    _button = value;
    markNeedsSemanticsUpdate();
  }

  bool? _enabled;
  set enabled(bool? value) {
    if (value == _enabled) return;
    _enabled = value;
    markNeedsSemanticsUpdate();
  }

  bool? _selected;
  set selected(bool? value) {
    if (value == _selected) return;
    _selected = value;
    markNeedsSemanticsUpdate();
  }

  /// The control's box, grown to [minSize] on each short axis.
  Rect get _reach {
    final extraWidth = math.max(0.0, _minSize.width - size.width);
    final extraHeight = math.max(0.0, _minSize.height - size.height);
    return Rect.fromLTWH(
      -extraWidth * (1 + _anchor.x) / 2,
      -extraHeight * (1 + _anchor.y) / 2,
      size.width + extraWidth,
      size.height + extraHeight,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final control = child;
    if (control == null || !_reach.contains(position)) return false;
    if (_neighbourOwns(position)) return false;
    final onto = Offset(
      position.dx.clamp(1.0, math.max(1.0, size.width - 1)),
      size.height / 2,
    );
    final hit = result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(onto),
      position: onto,
      hitTest: (result, _) => control.hitTest(result, position: onto),
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }

  /// Whether a sibling band has the better claim on [position], a point in
  /// this band but off this control. A sibling control drawn there keeps it,
  /// and a gap shared with a sibling band splits at its middle. Without
  /// this, the parent's last-child-first order hands the lower of two rows
  /// of chips the whole gap and the bottom of the pill above it.
  ///
  /// Only sibling bands count. Text or a spacer beside the chip still lets
  /// the band reach over it, which is the point of the band.
  bool _neighbourOwns(Offset position) {
    final data = parentData;
    if (data is! ContainerBoxParentData<RenderBox>) return false;
    final own = data.offset & size;
    final point = position + data.offset;
    final ownDistance = _distance(own, point);
    bool owns(RenderBox sibling) {
      if (sibling is! _RenderTapReach) return false;
      // Nearer by box is not enough: a sibling whose band stops short of the
      // point would take it from this one and then not answer it.
      final o = (sibling.parentData! as BoxParentData).offset;
      return sibling._reach.shift(o).contains(point) &&
          _distance(o & sibling.size, point) < ownDistance;
    }

    for (var s = data.previousSibling; s != null; s = _previous(s)) {
      if (owns(s)) return true;
    }
    for (var s = data.nextSibling; s != null; s = _next(s)) {
      if (owns(s)) return true;
    }
    return false;
  }

  static RenderBox? _previous(RenderBox box) =>
      (box.parentData! as ContainerBoxParentData<RenderBox>).previousSibling;

  static RenderBox? _next(RenderBox box) =>
      (box.parentData! as ContainerBoxParentData<RenderBox>).nextSibling;

  /// Squared distance from [point] to the nearest edge of [rect]; zero
  /// inside it.
  static double _distance(Rect rect, Offset point) {
    final dx = math.max(
      0.0,
      math.max(rect.left - point.dx, point.dx - rect.right),
    );
    final dy = math.max(
      0.0,
      math.max(rect.top - point.dy, point.dy - rect.bottom),
    );
    return dx * dx + dy * dy;
  }

  bool get _describes =>
      _button != null || _enabled != null || _selected != null;

  @override
  Rect get semanticBounds => _describes ? _reach : super.semanticBounds;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (!_describes) return;
    config.isSemanticBoundary = true;
    if (_button != null) config.isButton = _button!;
    if (_enabled != null) config.isEnabled = _enabled;
    if (_selected != null) config.isSelected = _selected!;
  }
}

/// Lets a row of small controls -- a one-row Wrap of chips, a settings row
/// with a kg/lb switch -- take taps up to [reach] above and below its own
/// box, and hands each one on as if it had landed on the row's nearest edge.
///
/// A chip's own band stops at its parent's box, and a one-row Wrap or a Row
/// is exactly as tall as its chips, so on its own a chip there answers only
/// its drawn pill. Wrapped in this, a tap just above or below the row lands
/// on the chip in line with it, and that chip's band takes it from there.
/// Nothing is laid out or drawn larger: the room comes from whatever padding
/// or gap the parent already has around the row, so the parent must have
/// that room -- a tap outside the parent's box never reaches here.
///
/// Like [_TapReach], the band sits on top of any earlier sibling it
/// overlaps, since a parent asks its last child first. Put it beside a gap,
/// a card's padding or plain text, not flush against another control. It
/// only ever hands a tap to its own child, and inside that the chips' bands
/// share out the point among themselves.
///
/// The default [reach] suits normal chips. A row of small ones (26 dp) needs
/// `reach: 11`, and 11 dp of the parent's room above and below, to reach 48.
///
/// [endReach] does the same past the row's far end, for a control that ends
/// it: a tap there lands on the row's last few pixels. The ancestor that
/// holds the room must pass the tap down, so this goes around the box the
/// padding is inside, not around a row the padding sits outside.
class FsTapRoom extends SingleChildRenderObjectWidget {
  const FsTapRoom({
    super.key,
    required Widget super.child,
    this.reach = 8,
    this.endReach = 0,
  });

  /// How far past the top and bottom edges a tap still counts. 8 dp takes a
  /// 32 dp row of normal chips to 48; a 26 dp row of small chips needs 11.
  final double reach;

  /// How far past the trailing edge a tap still counts: the padding a card
  /// leaves after its last control.
  final double endReach;

  @override
  RenderProxyBox createRenderObject(BuildContext context) => _RenderTapRoom(
    reach,
    endReach,
    Directionality.maybeOf(context) ?? TextDirection.ltr,
  );

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    (renderObject as _RenderTapRoom)
      ..reach = reach
      ..endReach = endReach
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

class _RenderTapRoom extends RenderProxyBox {
  _RenderTapRoom(this.reach, this.endReach, this.textDirection);

  double reach;
  double endReach;
  TextDirection textDirection;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final row = child;
    final rtl = textDirection == TextDirection.rtl;
    final left = rtl ? -endReach : 0.0;
    final right = size.width + (rtl ? 0 : endReach);
    if (row == null ||
        position.dx < left ||
        position.dx > right ||
        position.dy < -reach ||
        position.dy > size.height + reach) {
      return false;
    }
    final onto = Offset(
      position.dx.clamp(0.5, math.max(0.5, size.width - 0.5)),
      position.dy.clamp(0.5, math.max(0.5, size.height - 0.5)),
    );
    final hit = result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(onto),
      position: onto,
      hitTest: (result, _) => row.hitTest(result, position: onto),
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }
}
