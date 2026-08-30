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
    required this.accent,
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
  final Color text3;

  // accent + functional
  final Color accent;
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
    text3: Color(0xFF5D6873),
    accent: Color(0xFF7DFF5C),
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
    text3: Color(0xFF8B969C),
    accent: Color(0xFF0FB04A),
    accentDim: Color(0x210FB04A), // rgba(15,176,74,0.13)
    accentLine: Color(0x4D0FB04A), // rgba(15,176,74,0.30)
    onAccent: Color(0xFFFFFFFF),
    amber: Color(0xFFC98A10),
    red: Color(0xFFE0533D),
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
    Color? accent,
    Color? accentDim,
    Color? accentLine,
    Color? onAccent,
    Color? amber,
    Color? red,
    Color? blue,
    Color? violet,
  }) =>
      FsTokens(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        elev: elev ?? this.elev,
        line: line ?? this.line,
        line2: line2 ?? this.line2,
        text: text ?? this.text,
        text2: text2 ?? this.text2,
        text3: text3 ?? this.text3,
        accent: accent ?? this.accent,
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
      accent: Color.lerp(accent, other.accent, t)!,
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
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.elev,
      contentTextStyle: TextStyle(fontFamily: _fontFamily, color: t.text),
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
      side: BorderSide(color: t.line2, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
