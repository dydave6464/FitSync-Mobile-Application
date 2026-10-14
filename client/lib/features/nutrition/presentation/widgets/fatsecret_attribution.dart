import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme.dart';

final _platform = Uri.parse('https://platform.fatsecret.com');

/// FatSecret's required attribution, in the exact words its policy allows
/// (https://platform.fatsecret.com/attribution). Do not reword it.
class FatsecretAttribution extends StatelessWidget {
  const FatsecretAttribution({super.key, this.onOpen});

  /// Injectable for tests; defaults to opening the browser.
  final void Function(Uri)? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Center(
      child: TextButton(
        key: const Key('fatsecret.attribution'),
        onPressed: () => (onOpen ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(_platform),
        child: Text(
          'Powered by fatsecret Platform API',
          style: TextStyle(fontSize: 12, color: t.text3, decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}
