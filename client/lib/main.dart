import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';

void main() {
  runApp(const ProviderScope(child: FitSyncApp()));
}

class FitSyncApp extends ConsumerWidget {
  const FitSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'FitSync',
        debugShowCheckedModeBanner: false,
        theme: fsLightTheme(),
        darkTheme: fsDarkTheme(),
        // Never ThemeMode.system: the user picks explicitly in Settings, and
        // the stored choice is restored on launch.
        themeMode: ref.watch(themeModeProvider),
        home: const AppShell(),
      );
}
