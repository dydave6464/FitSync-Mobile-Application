import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/exercises/presentation/exercise_list_screen.dart' show describeError;
import 'features/onboarding/presentation/onboarding_flow.dart';

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
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _ShellError(
        message: describeError(error),
        onRetry: () => ref.invalidate(authControllerProvider),
      ),
      data: (state) => switch (state.status) {
        AuthStatus.signedOut => const SignInScreen(),
        AuthStatus.onboarding => const OnboardingFlow(),
        AuthStatus.ready => const PlanPlaceholder(),
      },
    );
  }
}

class _ShellError extends StatelessWidget {
  const _ShellError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Placeholders, not dead code.
//
// The shell's routing is built and tested before the screens it routes to
// exist. Task 9 replaces [PlanPlaceholder]; delete it when the real plan
// screen lands.
// ---------------------------------------------------------------------------

class PlanPlaceholder extends StatelessWidget {
  const PlanPlaceholder({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Your plan')));
}
