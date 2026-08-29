import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';

void main() {
  runApp(const ProviderScope(child: FitSyncApp()));
}

class FitSyncApp extends StatelessWidget {
  const FitSyncApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FitSync',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const AppShell(),
      );
}
