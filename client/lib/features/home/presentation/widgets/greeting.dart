import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../profile/domain/profile.dart';

/// The home app bar: initials, a date line, and the greeting.
///
/// [now] is injected rather than read from DateTime.now(), or the widget test
/// only passes on the day it happened to be written.
class Greeting extends StatelessWidget {
  const Greeting({super.key, required this.profile, required this.now});

  final Profile profile;
  final DateTime now;

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  List<String> get _words => profile.fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  String get _initials {
    final words = _words;
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  String get _firstName => _words.isEmpty ? 'there' : _words.first;

  /// Days since the account was created, counted in the viewer's local
  /// calendar rather than UTC. Local midnight is the boundary the user
  /// actually experiences, so [joined] — stored as UTC — is converted to
  /// local time before its date parts are taken. [now] needs no such
  /// conversion: it already carries the caller's local wall clock, per this
  /// class's contract.
  ///
  /// Computing in UTC instead would read a day behind for the first hours of
  /// every local day for anyone east of UTC, and comparing [joined]'s raw
  /// UTC date parts against a local [now] would pin the wrong baseline
  /// permanently for anyone who joined between local midnight and UTC
  /// midnight.
  ///
  /// Counted on date parts only so a late-evening join does not read as
  /// Day 2 the next morning. The join date itself is Day 1, never Day 0.
  int? get _dayCount {
    final joined = profile.joinedAt;
    if (joined == null) return null;
    final localJoined = joined.toLocal();
    final from =
        DateTime.utc(localJoined.year, localJoined.month, localJoined.day);
    final to = DateTime.utc(now.year, now.month, now.day);
    return to.difference(from).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final day = _dayCount;
    final weekday = _weekdays[now.weekday - 1];

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: t.line),
          ),
          child: Text(
            _initials,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text2,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                day == null ? weekday : '$weekday · Day $day',
                style: TextStyle(fontSize: 11, color: t.text3),
              ),
              const SizedBox(height: 2),
              Text('Kumusta, $_firstName', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ],
    );
  }
}
