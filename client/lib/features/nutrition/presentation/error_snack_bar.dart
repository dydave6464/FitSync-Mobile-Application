import 'package:flutter/material.dart';

import '../../../core/api_exception.dart';

/// Shows [message] in place of whatever message is up, not queued behind
/// it: with a screen reader, "Added …" and "Removed …" stay up until
/// dismissed, so an error queued behind them would never show.
///
/// With [onRetry] it carries a "Try again" action. An action would keep the
/// bar up until dismissed by default; it goes away on its own unless
/// [persist], which callers set for a screen reader (reaching the action by
/// swiping takes longer than the bar's four seconds).
void showErrorSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  VoidCallback? onRetry,
  bool persist = false,
}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    persist: persist,
    action: onRetry == null ? null : SnackBarAction(label: 'Try again', onPressed: onRetry),
  ));
}

/// Whether sending the same request again may go through: the phone could
/// not reach the server, the server failed, or its answer was garbled (a
/// proxy's error page). A refusal the server named -- no such entry, a
/// value out of range -- would only be refused again.
bool retryCanFix(Object error) =>
    error is ApiException && const {'NETWORK_ERROR', 'INTERNAL_ERROR', 'INVALID_RESPONSE'}.contains(error.code);

/// Runs [save]. If it fails, says [failure] and why (see `userMessage`).
/// When a retry can fix it, the message carries "Try again", which runs the
/// same [save] again, as often as it takes: what the user chose is kept in
/// the closure, so nothing has to be typed or picked twice. [onSaved] gets
/// the result once a save goes through.
Future<void> saveOrOfferRetry<T>(
  ScaffoldMessengerState messenger, {
  required Future<T> Function() save,
  required String failure,
  required bool persist,
  void Function(T saved)? onSaved,
}) async {
  final T saved;
  try {
    saved = await save();
  } catch (e) {
    showErrorSnackBar(
      messenger,
      '$failure ${userMessage(e)}',
      persist: persist,
      onRetry: !retryCanFix(e)
          ? null
          : () => saveOrOfferRetry(messenger, save: save, failure: failure, persist: persist, onSaved: onSaved),
    );
    return;
  }
  onSaved?.call(saved);
}
