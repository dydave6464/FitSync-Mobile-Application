import 'package:flutter/material.dart';

/// A Material icon standing in for [equipment] when artwork is unavailable.
///
/// Material rather than a licensed set: it ships with Flutter under Apache
/// 2.0, needs no attribution, no assets and no dependency, and it takes the
/// theme's colour like every other icon here. Flaticon's free tier would put
/// an author credit obligation inside the app and another entry in
/// THIRD_PARTY_LICENSES.md for artwork that is only ever a fallback.
///
/// Two vocabularies arrive here. The plan and swap paths send curated display
/// names ('Bodyweight', 'Machines'); `GET /exercises` sends the raw catalogue
/// tag ('body weight', 'smith machine'). Matching on lowercased keywords reads
/// both, and covers the children seed-equipment.js folds under a parent
/// without listing every one.
///
/// Three of these are honest approximations -- Material has no barbell,
/// kettlebell or resistance band -- so a barbell shares the dumbbell's icon
/// rather than borrowing something unrelated.
IconData equipmentIcon(String? equipment) {
  final name = (equipment ?? '').toLowerCase();

  // Checked before 'bar': 'barbell' contains it, and a pull-up bar is a
  // different thing from a loaded bar.
  if (name.contains('pull-up') || name.contains('pullup')) {
    return Icons.sports_gymnastics;
  }
  if (name.contains('body weight') || name.contains('bodyweight')) {
    return Icons.accessibility_new;
  }
  if (name.contains('machine') || name.contains('cable')) {
    return Icons.precision_manufacturing;
  }
  if (name.contains('kettlebell')) return Icons.sports_volleyball;
  if (name.contains('band')) return Icons.waves;
  if (name.contains('bench')) return Icons.airline_seat_flat;

  // The default, and where barbells land: a dumbbell is the one piece of gym
  // equipment Material draws, and it reads as "weights" generally.
  return Icons.fitness_center;
}
