import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../data/step_permission.dart';
import 'activity_screen.dart';
import 'providers.dart';

const _points = [
  "Uses your phone's motion sensor — no watch needed",
  'Works without internet',
  'Estimates kcal, km and active minutes',
  'Only daily totals are saved to your account',
];

/// Shown the first time the steps tile is tapped: explains step counting,
/// then asks the phone. "Not now" leaves the OS prompt unspent, so Home can
/// offer it again.
class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key, this.onGoToProfile});

  final VoidCallback? onGoToProfile;

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  bool _busy = false;

  Future<void> _start() async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    StepAccess access;
    try {
      access = await ref.read(stepAccessProvider.notifier).request();
    } catch (_) {
      access = StepAccess.refused;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (access == StepAccess.granted) {
      ref.invalidate(activityProvider);
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ActivityScreen(onGoToProfile: widget.onGoToProfile),
        ),
      );
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Count your steps')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            const Center(
              child: FsIconTile(
                icon: Icons.directions_walk,
                selected: true,
                size: 64,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'FitSync counts your steps all day, automatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 22),
            for (final point in _points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: t.accentText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(fontSize: 14, color: t.text, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            FsButton(
              key: const Key('activity.start'),
              label: 'Start counting my steps',
              busy: _busy,
              onPressed: _busy ? null : _start,
            ),
            const SizedBox(height: 8),
            FsButton(
              key: const Key('activity.notNow'),
              label: 'Not now',
              kind: FsButtonKind.ghost,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
