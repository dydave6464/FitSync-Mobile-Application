import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/widgets/fs_kit.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/exercises/presentation/exercise_list_screen.dart' show describeError;
import 'features/onboarding/presentation/onboarding_flow.dart';
import 'features/plans/presentation/plan_screen.dart';

/// Chooses the first screen from auth state, and nothing else.
///
/// Keeping the decision in one place is what lets every screen below it stay
/// ignorant of tokens and of why it is on screen.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return auth.when(
      loading: () => Scaffold(
        backgroundColor: context.fs.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _ShellError(
        message: describeError(error),
        onRetry: () => ref.invalidate(authControllerProvider),
      ),
      data: (state) => switch (state.status) {
        AuthStatus.signedOut => const SignInScreen(),
        AuthStatus.onboarding => const OnboardingFlow(),
        AuthStatus.ready => const PlanScreen(),
      },
    );
  }
}

class _ShellError extends StatelessWidget {
  const _ShellError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Scaffold(
      backgroundColor: t.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
              ),
              const SizedBox(height: 20),
              FsButton(label: 'Retry', small: true, onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
