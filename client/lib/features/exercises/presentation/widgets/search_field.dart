import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/fs_kit.dart';
import '../providers.dart';

/// The catalogue's search box.
///
/// Sole writer of [SelectedFilters.search], which is what lets the box hold
/// the text and the provider hold the query with no risk of the two
/// disagreeing: nothing else clears the term, so nothing has to push a value
/// back into this controller.
class ExerciseSearchField extends ConsumerStatefulWidget {
  const ExerciseSearchField({super.key});

  @override
  ConsumerState<ExerciseSearchField> createState() =>
      _ExerciseSearchFieldState();
}

class _ExerciseSearchFieldState extends ConsumerState<ExerciseSearchField> {
  /// How long typing has to stop before the term is applied.
  ///
  /// Writing the term on every keystroke rebuilds the list provider on every
  /// keystroke, which is a request per character against a 1,200-row
  /// catalogue -- and their answers can land out of order, leaving the list
  /// showing whichever response was slowest rather than what the box says.
  static const _debounce = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _timer;

  @override
  void dispose() {
    // Before the controller: a timer that fires after this State is gone
    // reads a disposed notifier.
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _apply(String raw) {
    final term = raw.trim();
    ref.read(selectedFiltersProvider.notifier)
        // Empty is null rather than '': the two mean the same thing to the
        // endpoint, but only null makes `isEmpty` -- and so the chip strip's
        // Clear -- agree that nothing is being searched for.
        .setSearch(term.isEmpty ? null : term);
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _apply(value));
  }

  void _clear() {
    // Cancelled, or a debounce still pending from the last keystroke would
    // re-apply the term a moment after the box emptied.
    _timer?.cancel();
    _controller.clear();
    _apply('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => FsField(
          fieldKey: const Key('library.search'),
          controller: _controller,
          hint: 'Search exercises',
          icon: Icons.search,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (text) {
            // The keyboard's own search key must not wait out the debounce:
            // the user has said they are finished typing.
            _timer?.cancel();
            _apply(text);
          },
          trailing: value.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('library.search.clear'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear search',
                  onPressed: _clear,
                ),
        ),
      ),
    );
  }
}
