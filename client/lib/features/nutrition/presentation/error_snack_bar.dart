import 'package:flutter/material.dart';

/// Shows [message] in place of whatever message is up, not queued behind
/// it: with a screen reader, "Added …" and "Removed …" stay up until
/// dismissed, so an error queued behind them would never show.
void showErrorSnackBar(ScaffoldMessengerState messenger, String message) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
