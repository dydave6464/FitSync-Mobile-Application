import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/admin_repository.dart';
import '../domain/admin_models.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

/// Which admin tab is current: 0 Overview, 1 Users, 2 Content, 3 Revenue.
///
/// [usersFilter] is a one-off request from whoever switched the tab, such as
/// Overview's Pro members card asking for `'pro'`. Null means "leave the
/// Users tab's filter as it is", which is what a tap on the bar sends.
typedef AdminTabState = ({int index, String? usersFilter});

class AdminTab extends Notifier<AdminTabState> {
  @override
  AdminTabState build() => (index: 0, usersFilter: null);

  void select(int index, {String? usersFilter}) =>
      state = (index: index, usersFilter: usersFilter);
}

/// autoDispose, so the next admin to sign in opens on Overview rather than
/// on the tab the last one left.
final adminTabProvider = NotifierProvider.autoDispose<AdminTab, AdminTabState>(
  AdminTab.new,
);

/// The Overview tab's figures. autoDispose, like every admin provider, so
/// nothing one admin saw outlives their sign-out.
final adminOverviewProvider = FutureProvider.autoDispose<AdminOverview>(
  (ref) => ref.watch(adminRepositoryProvider).overview(),
  retry: apiRetryPolicy,
);

/// Today in Manila, `YYYY-MM-DD`: what "active 3 d ago" counts back from.
/// The users list carries no `today` of its own, unlike the overview.
final adminTodayProvider = Provider.autoDispose<String>(
  (ref) => manilaDayOf(DateTime.now()),
);

/// What the Users tab asks for: the search box's term and the chip, one of
/// `all`, `pro` and `suspended`.
typedef AdminUsersQuery = ({String q, String filter});

class AdminUsersQueryNotifier extends Notifier<AdminUsersQuery> {
  @override
  AdminUsersQuery build() {
    // Overview's cards ask for a filter through the tab state, whether the
    // Users tab has been opened yet or not.
    ref.listen(adminTabProvider, (_, next) {
      final filter = next.usersFilter;
      if (filter != null && filter != state.filter) {
        state = (q: state.q, filter: filter);
      }
    });
    return (q: '', filter: ref.read(adminTabProvider).usersFilter ?? 'all');
  }

  void setSearch(String q) {
    if (q != state.q) state = (q: q, filter: state.filter);
  }

  void setFilter(String filter) {
    if (filter != state.filter) state = (q: state.q, filter: filter);
  }
}

final adminUsersQueryProvider =
    NotifierProvider.autoDispose<AdminUsersQueryNotifier, AdminUsersQuery>(
      AdminUsersQueryNotifier.new,
    );

/// The trainees loaded so far for the current query.
class AdminUsersState {
  const AdminUsersState({
    required this.items,
    required this.page,
    required this.total,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<AdminUserRow> items;
  final int page;

  /// Every trainee the query matches, loaded or not.
  final int total;
  final bool hasMore;
  final bool loadingMore;

  AdminUsersState copyWith({
    List<AdminUserRow>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? loadingMore,
  }) => AdminUsersState(
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// The Users list, a page of 30 at a time, as the exercise library's
/// `ExerciseListNotifier` pages. A new query rebuilds it from page 1.
class AdminUsersNotifier extends AsyncNotifier<AdminUsersState> {
  /// Moves on with every build. A page asked for before a rebuild -- a new
  /// search, or the list refreshed after a suspension -- belongs to a list
  /// no longer shown and is dropped. Comparing the query alone would miss
  /// the refresh, which keeps the same query.
  int _generation = 0;

  @override
  Future<AdminUsersState> build() async {
    _generation++;
    final query = ref.watch(adminUsersQueryProvider);
    final result = await ref
        .watch(adminRepositoryProvider)
        .users(q: query.q, filter: query.filter);
    return AdminUsersState(
      items: result.users,
      page: result.page,
      total: result.total,
      hasMore: result.hasMore,
    );
  }

  /// Loads the next page onto the list. A failure keeps the pages already
  /// shown and is rethrown for the screen to report.
  ///
  /// Does nothing while the list is (re)loading: a refresh keeps the old
  /// pages in its loading state, and a page asked for on top of them would
  /// carry the new generation and so overwrite the refreshed list.
  Future<void> loadMore() async {
    if (state.isLoading) return;
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    final query = ref.read(adminUsersQueryProvider);
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(adminRepositoryProvider)
          .users(q: query.q, filter: query.filter, page: current.page + 1);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.users],
          page: next.page,
          total: next.total,
          hasMore: next.hasMore,
          loadingMore: false,
        ),
      );
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}

/// One trainee's account, for their page.
final adminUserProvider = FutureProvider.autoDispose
    .family<AdminUserDetail, int>(
      (ref, id) => ref.watch(adminRepositoryProvider).user(id),
      retry: apiRetryPolicy,
    );

final adminUsersProvider =
    AsyncNotifierProvider.autoDispose<AdminUsersNotifier, AdminUsersState>(
      AdminUsersNotifier.new,
      retry: apiRetryPolicy,
    );
