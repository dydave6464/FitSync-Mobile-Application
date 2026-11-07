import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/admin_models.dart';
import '../providers.dart';
import 'admin_widgets.dart';

/// The body of a Content segment (Animations, Meals): a search box, two
/// chips, and the list a page at a time, as the Users tab draws its own.
/// What is listed, and how one row looks, is the segment's.
///
/// Keys start with [keyPrefix]: `<prefix>.search`, `<prefix>.chip.<value>`,
/// `<prefix>.retry` and `<prefix>.clear`.
class AdminContentList<T> extends StatefulWidget {
  const AdminContentList({
    super.key,
    required this.keyPrefix,
    required this.searchHint,
    required this.noun,
    required this.query,
    required this.chips,
    required this.list,
    required this.emptyMessage,
    required this.onSearch,
    required this.onChip,
    required this.onLoadMore,
    required this.onRetryMore,
    required this.onRetry,
    required this.itemBuilder,
  });

  final String keyPrefix;
  final String searchHint;

  /// What the list holds, plural: `No <noun> match "q".`
  final String noun;
  final AdminContentQuery query;

  /// The chips' values and words, counts included.
  final List<({String value, String label})> chips;
  final AsyncValue<AdminListState<T, AdminPaged<T>>> list;

  /// What an empty list with no search says, for the chip that is on.
  final String emptyMessage;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onChip;

  /// Loads the next page. A failure is the list's `moreError`, shown in a
  /// Try again row at the end, whose button calls [onRetryMore].
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetryMore;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  State<AdminContentList<T>> createState() => _AdminContentListState<T>();
}

class _AdminContentListState<T> extends State<AdminContentList<T>> {
  /// One request per search, not one per key (the Users tab's rule).
  static const _debounce = Duration(milliseconds: 300);

  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Seeded from the query, which can outlive this box.
    _search.text = widget.query.q;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _apply(String text) => widget.onSearch(text.trim());

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _apply(text));
  }

  void _clearSearch() {
    // Cancelled, or a pending keystroke would bring the term back.
    _timer?.cancel();
    _search.clear();
    _apply('');
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // A failed page stops this until Try again (see onLoadMore).
    if (position.maxScrollExtent - position.pixels < 400) widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.keyPrefix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (context, value, _) => FsField(
              fieldKey: Key('$prefix.search'),
              controller: _search,
              hint: widget.searchHint,
              icon: Icons.search,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (text) {
                // The keyboard's search key means typing is finished.
                _timer?.cancel();
                _apply(text);
              },
              trailing: value.text.isEmpty
                  ? null
                  : IconButton(
                      key: Key('$prefix.search.clear'),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FsTapRoom(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in widget.chips)
                  FsChip(
                    key: Key('$prefix.chip.${chip.value}'),
                    label: chip.label,
                    exclusive: true,
                    selected: widget.query.chip == chip.value,
                    onTap: () => widget.onChip(chip.value),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: widget.list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FsRetry(
              fullScreen: true,
              message: userMessage(error),
              buttonKey: Key('$prefix.retry'),
              onRetry: widget.onRetry,
            ),
            data: _list,
          ),
        ),
      ],
    );
  }

  Widget _list(AdminListState<T, AdminPaged<T>> state) {
    final q = widget.query.q;
    if (state.items.isEmpty) {
      return ListView(
        children: [
          if (q.isNotEmpty)
            AdminEmpty(
              message: 'No ${widget.noun} match "$q".',
              actionLabel: 'Clear search',
              actionKey: Key('${widget.keyPrefix}.clear'),
              onAction: _clearSearch,
            )
          else
            AdminEmpty(message: widget.emptyMessage),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount:
          state.items.length +
          (state.loadingMore || state.moreError != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= state.items.length) {
          if (state.moreError case final error?) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FsRetry(
                message: userMessage(error),
                buttonKey: Key('${widget.keyPrefix}.more.retry'),
                onRetry: widget.onRetryMore,
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: widget.itemBuilder(context, state.items[i]),
        );
      },
    );
  }
}
