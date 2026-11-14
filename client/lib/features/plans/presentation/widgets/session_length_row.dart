import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';

/// Auto / 45 / 60 (spec 2026-11-14). Auto sends nothing and the generator
/// derives the length; its number comes from GET /plans/defaults and is left
/// off when that fetch has not answered.
class SessionLengthRow extends StatelessWidget {
  const SessionLengthRow({
    super.key,
    required this.chosen,
    required this.autoMinutes,
    required this.lengthReason,
    required this.onChanged,
  });

  /// The length picked by hand, or null for Auto.
  final int? chosen;

  /// What Auto would pick now, or null while that is unknown.
  final int? autoMinutes;

  /// Why Auto picked [autoMinutes] (`health`, `level`, ...).
  final String? lengthReason;

  final ValueChanged<int?> onChanged;

  /// Said only when 60 is chosen over an Auto that holds the user at 45:
  /// it explains the cap without blocking the choice.
  String? get _note {
    if (chosen != 60 || autoMinutes != 45) return null;
    return switch (lengthReason) {
      'health' => 'Your health check suggests 45 min. You can still choose 60.',
      'level' => 'Auto keeps beginners at 45 min. You can still choose 60.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final note = _note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('Session length'),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FsTapRoom(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FsChip(
                  key: const Key('gen.length.auto'),
                  label: autoMinutes == null
                      ? 'Auto'
                      : 'Auto · $autoMinutes min',
                  selected: chosen == null,
                  exclusive: true,
                  onTap: () => onChanged(null),
                ),
                for (final m in const [45, 60])
                  FsChip(
                    key: Key('gen.length.$m'),
                    label: '$m min',
                    selected: chosen == m,
                    exclusive: true,
                    onTap: () => onChanged(m),
                  ),
              ],
            ),
          ),
        ),
        Text(
          'Auto follows your goal, level and health check.',
          style: TextStyle(fontSize: 12, color: t.text3, height: 1.35),
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(
            note,
            key: const Key('gen.length.note'),
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
          ),
        ],
      ],
    );
  }
}
