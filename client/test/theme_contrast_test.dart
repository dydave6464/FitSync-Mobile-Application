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
}
