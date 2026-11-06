import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api_exception.dart';
import 'core/theme.dart';
import 'core/widgets/fs_kit.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/home/presentation/nav_shell.dart';
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
      loading: () => Scaffold(
        backgroundColor: context.fs.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      // The account could not be read. Try again is the usual way on; Sign
      // out is the way back to sign-in, so someone on the wrong account, or
      // one the server cannot load, is never stuck pressing Try again.
      error: (error, _) => Scaffold(
        backgroundColor: context.fs.bg,
        body: FsRetry(
          fullScreen: true,
          message: userMessage(error),
          onRetry: () => ref.invalidate(authControllerProvider),
          secondary: FsButton(
            key: const Key('signOut'),
            label: 'Sign out',
            kind: FsButtonKind.ghost,
            small: true,
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ),
      ),
      data: (state) => switch (state.status) {
        AuthStatus.signedOut => const SignInScreen(),
        AuthStatus.onboarding => const OnboardingFlow(),
        AuthStatus.ready => const NavShell(),
      },
    );
  }
}
