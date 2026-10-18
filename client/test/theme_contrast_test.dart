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

    test("the date picker writes today's date in the text green", () {
      final data = theme == 'light' ? fsLightTheme() : fsDarkTheme();
      final today = data.datePickerTheme.todayForegroundColor!;
      expect(today.resolve({}), t.accentText);
      // Picked, today sits on the green fill like any picked day.
      expect(today.resolve({WidgetState.selected}), t.onAccent);
    });

    test('a text button reads in the text green in the $theme theme', () {
      final data = theme == 'light' ? fsLightTheme() : fsDarkTheme();
      expect(
        data.textButtonTheme.style?.foregroundColor?.resolve({}),
        t.accentText,
      );
    });
  }

  test('the brand green stays as it is; only its text form darkens', () {
    expect(FsTokens.light.accent, const Color(0xFF0FB04A));
    // Dark mode's lime already reads at well over 4.5:1 on its surfaces.
    expect(FsTokens.dark.accentText, FsTokens.dark.accent);
  });
}
