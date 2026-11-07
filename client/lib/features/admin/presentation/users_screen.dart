import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/numbers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'providers.dart';
import 'widgets/admin_widgets.dart';

/// The admin's Users tab: every trainee, newest sign-ups first, searchable
/// by name or email and narrowed by All · Pro · Suspended. A row opens the
/// trainee's page, where an account is suspended or reinstated.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  /// How long typing has to stop before the list is asked again: one
  /// request per search, not one per key (the exercise library's rule).
  static const _debounce = Duration(milliseconds: 300);

  static const _filters = [
    ('all', 'All'),
    ('pro', 'Pro'),
    ('suspended', 'Suspended'),
  ];

  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Seeded from the query, which can outlive this box.
    _search.text = ref.read(adminUsersQueryProvider).q;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _apply(String text) =>
      ref.read(adminUsersQueryProvider.notifier).setSearch(text.trim());

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
    if (position.maxScrollExtent - position.pixels < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(adminUsersProvider.notifier).loadMore();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(adminUsersQueryProvider);
    final users = ref.watch(adminUsersProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Semantics(
              header: true,
              child: Text(
                'Users',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _search,
              builder: (context, value, _) => FsField(
                fieldKey: const Key('admin.users.search'),
                controller: _search,
                hint: 'Search name or email',
                icon: Icons.search,
                keyboardType: TextInputType.emailAddress,
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
                        key: const Key('admin.users.search.clear'),
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
                  for (final (value, label) in _filters)
                    FsChip(
                      key: Key('admin.users.filter.$value'),
                      label: label,
                      exclusive: true,
                      selected: query.filter == value,
                      onTap: () => ref
                          .read(adminUsersQueryProvider.notifier)
                          .setFilter(value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => FsRetry(
                fullScreen: true,
                message: userMessage(error),
                buttonKey: const Key('admin.users.retry'),
                onRetry: () => ref.invalidate(adminUsersProvider),
              ),
              data: (state) => _list(state, query),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(AdminUsersState state, AdminUsersQuery query) {
    final t = context.fs;
    final count = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        state.total == 1
            ? '1 trainee'
            : '${groupThousands(state.total.toDouble())} trainees',
        style: TextStyle(fontSize: 12, color: t.text3),
      ),
    );

    if (state.items.isEmpty) {
      return ListView(
        children: [
          count,
          if (query.q.isNotEmpty)
            AdminEmpty(
              message: 'No trainees match "${query.q}".',
              actionLabel: 'Clear search',
              actionKey: const Key('admin.users.clear'),
              onAction: _clearSearch,
            )
          else
            AdminEmpty(
              message: switch (query.filter) {
                'pro' => 'No Pro members yet.',
                'suspended' => 'No suspended accounts.',
                _ => 'No trainees yet.',
              },
            ),
        ],
      );
    }

    final today = ref.watch(adminTodayProvider);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: 1 + state.items.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) return count;
        final i = index - 1;
        if (i >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final user = state.items[i];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _UserRow(
            key: ValueKey('admin.user.${user.id}'),
            user: user,
            lastActive: lastActiveLabel(user.lastActiveOn, today),
            onTap: () {},
          ),
        );
      },
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    super.key,
    required this.user,
    required this.lastActive,
    required this.onTap,
  });

  final AdminUserRow user;
  final String lastActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final spoken = [
      user.fullName,
      user.email,
      if (user.isPro) 'Pro',
      if (user.suspended) 'Suspended',
      lastActive,
    ].join(', ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FsCard(
        small: true,
        onTap: onTap,
        child: Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Row(
            children: [
              InitialsAvatar(user.fullName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                    if (user.isPro || user.suspended) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (user.isPro) const StatusTag('Pro'),
                          if (user.suspended)
                            StatusTag('Suspended', color: t.red),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  lastActive,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: t.text3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
