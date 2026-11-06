import 'package:flutter/material.dart';

/// The FitSync design tokens, ported from the prototype's `styles.css`.
///
/// The prototype defines two palettes: a dark one on `:root` and a light one
/// under `html.theme-light`. Both are here, and every colour a screen uses
/// comes from this object rather than a literal, so the two stay in step.
@immutable
class FsTokens extends ThemeExtension<FsTokens> {
  const FsTokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.elev,
    required this.line,
    required this.line2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.control,
    required this.accent,
    required this.accentText,
    required this.accentFill,
    required this.accentDim,
    required this.accentLine,
    required this.onAccent,
    required this.amber,
    required this.red,
    required this.blue,
    required this.violet,
  });

  // surfaces
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color elev;
  final Color line;
  final Color line2;

  // text
  final Color text;
  final Color text2;

  /// Captions: dates, units, the words under figures. 4.5:1 or better on the
  /// plain surfaces (bg, surface, surface2, elev), but not on the accent
  /// tint: where `FsCard`'s accent gradient is strongest (the accent at 0.16)
  /// it drops below that, to about 4.2:1 over the light page and 3.6:1 over
  /// a dark card. So secondary text on `FsCard(accent: true)` or on an
  /// [accentDim] surface uses [text2], which holds 4.5:1 there, not [text3].
  final Color text3;

  /// The outline that says a control is there: an unticked checkbox, an
  /// unselected radio ring, an outlined button. WCAG asks 3:1 for that
  /// boundary on every surface; [line2] is a hairline at about 1.4:1, so it
  /// stays for dividers and card edges only.
  final Color control;

  // accent + functional
  final Color accent;

  /// The accent where it is read rather than seen: link and text-button
  /// labels, green figures, the current tab, icons that carry meaning. Fills
  /// keep [accent], or [accentFill] where the fill is data. The two differ
  /// only in the light theme, where the brand green on white is 2.87:1 and
  /// reads as faint text.
  final Color accentText;

  /// The accent where it is data: progress bars, chart bars, state dots.
  /// A fill like that is read for how full it is, so it needs 3:1 on every
  /// surface, which the light theme's brand green (2.45:1 on surface2) is
  /// not. Buttons, chips and the nav button keep [accent]: there the green
  /// is the brand, not a measure.
  final Color accentFill;
  final Color accentDim;
  final Color accentLine;
  final Color onAccent;
  final Color amber;
  final Color red;
  final Color blue;
  final Color violet;

  /// `:root` — the prototype's primary look.
  static const dark = FsTokens(
    bg: Color(0xFF0A0D11),
    surface: Color(0xFF11161D),
    surface2: Color(0xFF161D25),
    elev: Color(0xFF1D2630),
    line: Color(0x12FFFFFF), // rgba(255,255,255,0.07)
    line2: Color(0x21FFFFFF), // rgba(255,255,255,0.13)
    text: Color(0xFFEEF2F5),
    text2: Color(0xFF97A3AD),
    // Lifted from #5D6873 (3.2:1 on cards) to read at 4.5:1 or better on
    // every plain surface, still dimmer than text2 (parked §32). Not on the
    // accent tint: see [text3].
    text3: Color(0xFF838E98),
    // text3's grey: 4.5:1 or better on every surface (4.58:1 on elev, the
    // lowest), where line2 was 1.4:1.
    control: Color(0xFF838E98),
    accent: Color(0xFF7DFF5C),
    // The lime already reads at well over 4.5:1 on every dark surface.
    accentText: Color(0xFF7DFF5C),
    // The lime already stands out at well over 3:1 on every dark surface.
    accentFill: Color(0xFF7DFF5C),
    accentDim: Color(0x247DFF5C), // rgba(125,255,92,0.14)
    accentLine: Color(0x577DFF5C), // rgba(125,255,92,0.34)
    onAccent: Color(0xFF06140A),
    amber: Color(0xFFFFCE4F),
    red: Color(0xFFFF7A6B),
    blue: Color(0xFF62CDFF),
    violet: Color(0xFFB69BFF),
  );

  /// `html.theme-light`. The accent deepens to #0FB04A so it still reads as
  /// text and icon colour on white — the bright lime does not.
  static const light = FsTokens(
    bg: Color(0xFFF3F5F3),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEAEEEC),
    elev: Color(0xFFFFFFFF),
    line: Color(0x17111C17), // rgba(17,28,23,0.09)
    line2: Color(0x26111C17), // rgba(17,28,23,0.15)
    text: Color(0xFF0F1613),
    text2: Color(0xFF55636B),
    // Darkened from #8B969C (3.0:1 on white) to read at 4.5:1 or better on
    // every plain surface, still lighter than text2 (parked §32). Not on the
    // accent tint: see [text3].
    text3: Color(0xFF616C73),
    // text3's grey: 4.6:1 or better on every surface, where line2 was 1.4:1.
    control: Color(0xFF616C73),
    accent: Color(0xFF0FB04A),
    // A deeper shade of the same green for words: 4.5:1 or better on every
    // surface and on the green's own tint (accentDim), which the brand green
    // is not. Still plainly the accent beside a filled button (parked §32).
    accentText: Color(0xFF087530),
    // A shade deeper than the brand green, for bars read as data: 3.1:1 or
    // better on every surface, where the brand green is 2.45:1 on surface2.
    accentFill: Color(0xFF0C9A40),
    accentDim: Color(0x210FB04A), // rgba(15,176,74,0.13)
    accentLine: Color(0x4D0FB04A), // rgba(15,176,74,0.30)
    // Dark, as in the dark theme: white on this green was 2.87:1, and the
    // brand green stays exactly as it is (parked §32).
    onAccent: Color(0xFF06140A),
    amber: Color(0xFFC98A10),
    // Darker than the prototype's #E0533D, which was 3.8:1 on white: red
    // labels the destructive choices and errors, so it is read as text.
    red: Color(0xFFC43A26),
    blue: Color(0xFF1F8FD0),
    violet: Color(0xFF7A5CF0),
  );

  @override
  FsTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? elev,
    Color? line,
    Color? line2,
    Color? text,
    Color? text2,
    Color? text3,
    Color? control,
    Color? accent,
    Color? accentText,
    Color? accentFill,
    Color? accentDim,
    Color? accentLine,
    Color? onAccent,
    Color? amber,
    Color? red,
    Color? blue,
    Color? violet,
  }) => FsTokens(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    elev: elev ?? this.elev,
    line: line ?? this.line,
    line2: line2 ?? this.line2,
    text: text ?? this.text,
    text2: text2 ?? this.text2,
    text3: text3 ?? this.text3,
    control: control ?? this.control,
    accent: accent ?? this.accent,
    accentText: accentText ?? this.accentText,
    accentFill: accentFill ?? this.accentFill,
    accentDim: accentDim ?? this.accentDim,
    accentLine: accentLine ?? this.accentLine,
    onAccent: onAccent ?? this.onAccent,
    amber: amber ?? this.amber,
    red: red ?? this.red,
    blue: blue ?? this.blue,
    violet: violet ?? this.violet,
  );

  @override
  FsTokens lerp(covariant FsTokens? other, double t) {
    if (other == null) return this;
    return FsTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      elev: Color.lerp(elev, other.elev, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      control: Color.lerp(control, other.control, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      red: Color.lerp(red, other.red, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
    );
  }
}

/// Corner radii, from the `--r-*` custom properties.
abstract final class FsRadius {
  static const card = 22.0;
  static const md = 16.0;
  static const sm = 11.0;
  static const pill = 999.0;
}

const _fontFamily = 'SpaceGrotesk';
const fsMonoFamily = 'JetBrainsMono';

/// Reads the tokens for the current theme. Every screen goes through this.
///
/// Falls back to the palette matching the ambient brightness when the
/// extension is absent — a widget rendered outside [fsDarkTheme]/[fsLightTheme]
/// (a bare `MaterialApp` in a widget test, say) then still draws correctly
/// instead of throwing on a null check.
extension FsThemeX on BuildContext {
  FsTokens get fs {
    final theme = Theme.of(this);
    return theme.extension<FsTokens>() ??
        (theme.brightness == Brightness.light ? FsTokens.light : FsTokens.dark);
  }
}

TextTheme _textTheme(FsTokens t) => TextTheme(
  // .h1 — 25px / 700 / -0.035em
  headlineSmall: TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.875,
    height: 1.05,
    color: t.text,
  ),
  // .h2 — 19px / 700 / -0.03em
  titleLarge: TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.57,
    color: t.text,
  ),
  // .h3 — 15px / 600 / -0.02em
  titleMedium: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: t.text,
  ),
  // body — 13px / 600
  bodyMedium: TextStyle(fontSize: 13, color: t.text),
  // .t-sm — 12.5px
  bodySmall: TextStyle(fontSize: 12.5, color: t.text2),
  // .btn — 15px / 700 / -0.01em
  labelLarge: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    color: t.text,
  ),
);

/// `.eyebrow` — mono, 10.5px, uppercase, wide tracking. Section labels and
/// step counters use this; it is the design's most recognisable detail.
TextStyle fsEyebrow(FsTokens t) => TextStyle(
  fontFamily: fsMonoFamily,
  fontSize: 10.5,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.47, // 0.14em
  color: t.text3,
);

/// `.num` — mono, for figures.
TextStyle fsNum(FsTokens t, {double size = 13}) => TextStyle(
  fontFamily: fsMonoFamily,
  fontSize: size,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.13,
  color: t.text,
);

ThemeData _build(FsTokens t, Brightness brightness) {
  final textTheme = _textTheme(t);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    extensions: [t],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accent,
      onSecondary: t.onAccent,
      error: t.red,
      onError: t.onAccent,
      surface: t.surface,
      onSurface: t.text,
      outline: t.line2,
      surfaceContainerHighest: t.surface2,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.735,
        color: t.text,
      ),
      iconTheme: IconThemeData(color: t.text2, size: 19),
    ),
    iconTheme: IconThemeData(color: t.text2),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.surface2,
    ),
    // "Show all", "Past month", dialog answers: words in green, so the text
    // green rather than the colour scheme's primary, which is the brand fill.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accentText),
    ),
    // Unset, M3 drew the label in primary (the brand green, 2.87:1 on white)
    // inside a line2 outline that barely read as a control.
    //
    // The outline follows the state, as M3's own does: dim while disabled,
    // so a dead button does not look live, and the text green while focused
    // -- M3 uses primary there, the brand green, under 3:1 on white.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: t.accentText).copyWith(
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.disabled)
                ? t.text.withValues(alpha: 0.12)
                : s.contains(WidgetState.focused)
                ? t.accentText
                : t.control,
          ),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.elev,
      contentTextStyle: TextStyle(fontFamily: _fontFamily, color: t.text),
      // Left unset, Undo fell back to inversePrimary -- onAccent's near
      // black, all but invisible on the dark theme's bar.
      actionTextColor: t.accentText,
    ),
    // M3 writes today's date in primary, the brand green, which is 2.87:1
    // as text on the light theme's dialog.
    datePickerTheme: DatePickerThemeData(
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.accentText,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.text3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.surface2,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.line),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(t.onAccent),
      side: BorderSide(color: t.control, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    // One chrome for every sheet (PT-22): the surface, the card's corners
    // and the prototype's 38 x 4 line2 handle. A sheet that must hold back a
    // drag turns Material's handle off and draws FsSheetHandle inside its
    // guard instead.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FsRadius.card),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: t.line2,
      dragHandleSize: const Size(38, 4),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: TextStyle(fontSize: 11, color: t.text3),
      iconColor: t.text2,
      selectedColor: t.text,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
  );
}

ThemeData fsDarkTheme() => _build(FsTokens.dark, Brightness.dark);
ThemeData fsLightTheme() => _build(FsTokens.light, Brightness.light);
