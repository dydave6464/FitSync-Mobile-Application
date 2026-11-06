import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// The top of a training bottom sheet, as the prototype draws every sheet
/// (ScreenStartSheet, ScreenShareProgress): a 38 x 4 handle, the title, and
/// an × that closes it.
///
/// One header for the jump, rest, share, pain-question and equipment sheets,
/// which had grown five different tops -- two with no visible way to close
/// but a swipe. The same shape as the start-workout sheet's own header.
///
/// [onClose] defaults to popping the sheet with no result, which every
/// caller reads as "dismissed". Padding is the sheet's own business: this
/// fills whatever width it is given.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.onClose,
    this.closeKey,
  });

  final String title;
  final VoidCallback? onClose;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Center(
            child: Container(
              key: const Key('sheet.handle'),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: t.line2,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
        Row(
          children: [
            // Expanded, so at 2x text a long question wraps instead of
            // pushing the close button off the sheet.
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: t.text),
                ),
              ),
            ),
            IconButton(
              key: closeKey,
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 18),
              color: t.text2,
              onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ],
    );
  }
}
