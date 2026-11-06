import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';

/// WCAG's contrast ratio, from Flutter's own relative luminance.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  // Red is read, not just seen: the destructive choice in every "are you
  // sure" dialog, Sign out, and error messages. Those are normal-size labels,
  // so WCAG AA's 4.5:1 applies, on the page, cards and dialogs alike.
  for (final (theme, t) in [
    ('light', FsTokens.light),
    ('dark', FsTokens.dark),
  ]) {
    test('red text reads at 4.5:1 or better in the $theme theme', () {
      for (final (name, background) in [
        ('page', t.bg),
        ('card', t.surface),
        ('dialog', t.elev),
      ]) {
        expect(
          _contrast(t.red, background),
          greaterThanOrEqualTo(4.5),
          reason: 'red on the $name background',
        );
      }
    });
  }

  // Captions (text3) are read too: dates, units, the words under figures.
  // They stay dimmer than text2, so a caption still looks like one.
  for (final (theme, t) in [
    ('light', FsTokens.light),
    ('dark', FsTokens.dark),
  ]) {
    test('caption text reads at 4.5:1 or better in the $theme theme', () {
      for (final (name, background) in [
        ('page', t.bg),
        ('card', t.surface),
        ('chip', t.surface2),
        ('dialog', t.elev),
      ]) {
        expect(
          _contrast(t.text3, background),
          greaterThanOrEqualTo(4.5),
          reason: 'text3 on the $name background',
        );
      }
      expect(
        _contrast(t.text3, t.surface),
        lessThan(_contrast(t.text2, t.surface)),
        reason: 'captions stay quieter than secondary text',
      );
    });

    // Every primary button's label (Continue, Start, Resume it…) sits on
    // the accent green; the brand colour stays, the label does the work.
    test('labels on the green read at 4.5:1 or better in the $theme theme', () {
      expect(_contrast(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
    });

    // Green is also read as words: "Show all", "Past month", "+12%", the
    // current tab. The brand green fills buttons, rings and bars; what is
    // read takes accentText, on every surface and on the green's own tint.
    test('green text reads at 4.5:1 or better in the $theme theme', () {
      for (final (name, background) in [
        ('page', t.bg),
        ('card', t.surface),
        ('chip', t.surface2),
        ('dialog', t.elev),
        ('green tint on the page', Color.alphaBlend(t.accentDim, t.bg)),
        ('green tint on a card', Color.alphaBlend(t.accentDim, t.surface)),
      ]) {
        expect(
          _contrast(t.accentText, background),
          greaterThanOrEqualTo(4.5),
          reason: 'accentText on the $name background',
        );
      }
    });

    // Undo on a snack bar: unset, M3 drew it in inversePrimary, which is the
    // near-black onAccent here -- 1.2:1 on the dark theme's bar.
    test('a snack bar action reads at 4.5:1 in the $theme theme', () {
      final data = theme == 'light' ? fsLightTheme() : fsDarkTheme();
      final action = data.snackBarTheme.actionTextColor;
      expect(action, t.accentText);
      expect(
        _contrast(action!, data.snackBarTheme.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
    });

    test(
      "the date picker writes today's date in the text green in the $theme theme",
      () {
        final data = theme == 'light' ? fsLightTheme() : fsDarkTheme();
        final today = data.datePickerTheme.todayForegroundColor!;
        expect(today.resolve({}), t.accentText);
        // Picked, today sits on the green fill like any picked day.
        expect(today.resolve({WidgetState.selected}), t.onAccent);
      },
    );

    test('a text button reads in the text green in the $theme theme', () {
      final data = theme == 'light' ? fsLightTheme() : fsDarkTheme();
      expect(
        data.textButtonTheme.style?.foregroundColor?.resolve({}),
        t.accentText,
      );
    });
  }

  for (final (theme, t) in [
    ('light', FsTokens.light),
    ('dark', FsTokens.dark),
  ]) {
    // An unticked checkbox or radio ring is the only sign a control is
    // there: WCAG 1.4.11 asks 3:1 for that boundary. line2 was about 1.4:1.
    test('control outlines read at 3:1 in the $theme theme', () {
      for (final (name, bg) in [
        ('page', t.bg),
        ('card', t.surface),
        ('chip', t.surface2),
      ]) {
        expect(
          _contrast(Color.alphaBlend(t.control, bg), bg),
          greaterThanOrEqualTo(3.0),
          reason: 'control on the $name background',
        );
      }
    });

    // Progress and chart bars are the data itself: 3:1 against what they
    // sit on. The light brand green is 2.45:1 on surface2.
    test('data fills read at 3:1 in the $theme theme', () {
      for (final (name, bg) in [
        ('page', t.bg),
        ('card', t.surface),
        ('chip', t.surface2),
      ]) {
        expect(
          _contrast(t.accentFill, bg),
          greaterThanOrEqualTo(3.0),
          reason: 'accentFill on the $name background',
        );
      }
    });

    // Unset, M3 drew an OutlinedButton's label in primary, the brand green:
    // 2.87:1 on white.
    test('outlined button text reads at 4.5:1 in the $theme theme', () {
      final themeData = theme == 'light' ? fsLightTheme() : fsDarkTheme();
      final style = themeData.outlinedButtonTheme.style!;
      final fg = style.foregroundColor!.resolve({})!;
      expect(fg, t.accentText);
      expect(_contrast(fg, t.surface), greaterThanOrEqualTo(4.5));
      expect(style.side!.resolve({})!.color, t.control);
    });

    test(
      'an unticked checkbox is outlined in the control colour in the $theme theme',
      () {
        final themeData = theme == 'light' ? fsLightTheme() : fsDarkTheme();
        expect(themeData.checkboxTheme.side!.color, t.control);
      },
    );

    // FsCard(accent: true) fades the accent from 0.16 at its top-left corner
    // to 0.03, over the page or a card. Secondary text there takes text2.
    test(
      'text2 reads at 4.5:1 on the strongest accent tint in the $theme theme',
      () {
        for (final (name, under) in [('page', t.bg), ('card', t.surface)]) {
          final tint = Color.alphaBlend(
            t.accent.withValues(alpha: 0.16),
            under,
          );
          expect(
            _contrast(t.text2, tint),
            greaterThanOrEqualTo(4.5),
            reason: 'text2 on the tint over the $name background',
          );
        }
      },
    );
  }

  test('the brand green stays as it is; only its text form darkens', () {
    expect(FsTokens.light.accent, const Color(0xFF0FB04A));
    // Dark mode's lime already reads at well over 4.5:1 on its surfaces.
    expect(FsTokens.dark.accentText, FsTokens.dark.accent);
  });
}
