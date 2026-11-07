import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

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
    this.moreError,
  });

  final List<AdminUserRow> items;
  final int page;

  /// Every trainee the query matches, loaded or not.
  final int total;
  final bool hasMore;
  final bool loadingMore;

  /// Why the last next page failed. While set, no next page is asked for
  /// until [AdminUsersNotifier.retryMore]; a rebuild starts without it.
  final Object? moreError;

  /// Keeps [moreError]; a successful next page is built from a state that
  /// has none.
  AdminUsersState copyWith({
    List<AdminUserRow>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? loadingMore,
    Object? moreError,
  }) => AdminUsersState(
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: moreError ?? this.moreError,
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
    // Overview's cards hand over with a filter: the list is fetched again
    // even when the chip is already on, so its count is no older than the
    // figure just tapped. A tap on the bar (no filter) keeps it as it is.
    ref.listen(adminTabProvider, (_, next) {
      if (next.usersFilter != null) ref.invalidateSelf();
    });
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
  /// shown and is kept as [AdminUsersState.moreError] for the screen's
  /// Try again row; until then no next page is asked for, so every scroll
  /// near the end does not send (and fail) another request.
  ///
  /// Does nothing while the list is (re)loading: a refresh keeps the old
  /// pages in its loading state, and a page asked for on top of them would
  /// carry the new generation and so overwrite the refreshed list.
  Future<void> loadMore() async {
    if (state.isLoading) return;
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.moreError != null) {
      return;
    }
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
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false, moreError: error));
    }
  }

  /// The Try again row: asks for the page that failed once more.
  Future<void> retryMore() async {
    final current = state.value;
    if (state.isLoading || current == null || current.moreError == null) {
      return;
    }
    state = AsyncData(
      AdminUsersState(
        items: current.items,
        page: current.page,
        total: current.total,
        hasMore: current.hasMore,
      ),
    );
    await loadMore();
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

/// What a Content list asks for: the search box's term and the chip that
/// is on (`pending`/`live` for Animations, `shown`/`hidden` for Meals).
typedef AdminContentQuery = ({String q, String chip});

class AdminContentQueryNotifier extends Notifier<AdminContentQuery> {
  AdminContentQueryNotifier(this._firstChip);

  final String _firstChip;

  @override
  AdminContentQuery build() => (q: '', chip: _firstChip);

  void setSearch(String q) {
    if (q != state.q) state = (q: q, chip: state.chip);
  }

  void setChip(String chip) {
    if (chip != state.chip) state = (q: state.q, chip: chip);
  }
}

/// The items of a Content list loaded so far, and the last page's answer,
/// which carries the chips' counts.
class AdminListState<T, P extends AdminPaged<T>> {
  const AdminListState({
    required this.items,
    required this.last,
    this.loadingMore = false,
    this.moreError,
  });

  final List<T> items;
  final P last;
  final bool loadingMore;

  /// Why the last next page failed, as [AdminUsersState.moreError].
  final Object? moreError;

  bool get hasMore => last.hasMore;
}

/// A Content list, a page of 30 at a time, paged as [AdminUsersNotifier]
/// pages the trainees (see there for why the generation is kept). A new
/// query rebuilds it from page 1.
abstract class AdminListNotifier<T, P extends AdminPaged<T>>
    extends AsyncNotifier<AdminListState<T, P>> {
  int _generation = 0;
  late AdminContentQuery _query;

  ProviderListenable<AdminContentQuery> get queryProvider;

  Future<P> fetch(AdminRepository repo, AdminContentQuery query, int page);

  @override
  Future<AdminListState<T, P>> build() async {
    _generation++;
    final query = _query = ref.watch(queryProvider);
    final first = await fetch(ref.watch(adminRepositoryProvider), query, 1);
    return AdminListState(items: first.items, last: first);
  }

  /// Loads the next page onto the list. A failure keeps the pages already
  /// shown and is kept as [AdminListState.moreError]: no next page is
  /// asked for again until [retryMore], as [AdminUsersNotifier.loadMore].
  Future<void> loadMore() async {
    if (state.isLoading) return;
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.moreError != null) {
      return;
    }
    final generation = _generation;
    state = AsyncData(
      AdminListState(
        items: current.items,
        last: current.last,
        loadingMore: true,
      ),
    );
    try {
      final next = await fetch(
        ref.read(adminRepositoryProvider),
        _query,
        current.last.page + 1,
      );
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        AdminListState(items: [...current.items, ...next.items], last: next),
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        AdminListState(
          items: current.items,
          last: current.last,
          moreError: error,
        ),
      );
    }
  }

  /// The Try again row: asks for the page that failed once more.
  Future<void> retryMore() async {
    final current = state.value;
    if (state.isLoading || current == null || current.moreError == null) {
      return;
    }
    state = AsyncData(AdminListState(items: current.items, last: current.last));
    await loadMore();
  }
}

final adminExercisesQueryProvider =
    NotifierProvider.autoDispose<AdminContentQueryNotifier, AdminContentQuery>(
      () => AdminContentQueryNotifier('pending'),
    );

class AdminExercisesNotifier
    extends AdminListNotifier<AdminExercise, AdminExercisesPage> {
  @override
  ProviderListenable<AdminContentQuery> get queryProvider =>
      adminExercisesQueryProvider;

  @override
  Future<AdminExercisesPage> fetch(
    AdminRepository repo,
    AdminContentQuery query,
    int page,
  ) => repo.exercises(status: query.chip, q: query.q, page: page);
}

/// The Animations list: exercise demos, pending or live.
final adminExercisesProvider =
    AsyncNotifierProvider.autoDispose<
      AdminExercisesNotifier,
      AdminListState<AdminExercise, AdminExercisesPage>
    >(AdminExercisesNotifier.new, retry: apiRetryPolicy);

final adminFoodsQueryProvider =
    NotifierProvider.autoDispose<AdminContentQueryNotifier, AdminContentQuery>(
      () => AdminContentQueryNotifier('shown'),
    );

class AdminFoodsNotifier extends AdminListNotifier<AdminFood, AdminFoodsPage> {
  @override
  ProviderListenable<AdminContentQuery> get queryProvider =>
      adminFoodsQueryProvider;

  @override
  Future<AdminFoodsPage> fetch(
    AdminRepository repo,
    AdminContentQuery query,
    int page,
  ) => repo.foods(show: query.chip, q: query.q, page: page);
}

/// The Meals list: FitSync's own foods, shown or hidden.
final adminFoodsProvider =
    AsyncNotifierProvider.autoDispose<
      AdminFoodsNotifier,
      AdminListState<AdminFood, AdminFoodsPage>
    >(AdminFoodsNotifier.new, retry: apiRetryPolicy);

/// The Ads list: every ad, newest first. Not paged: there are few.
final adminAdsProvider = FutureProvider.autoDispose<List<AdminAd>>(
  (ref) => ref.watch(adminRepositoryProvider).ads(),
  retry: apiRetryPolicy,
);

/// One Manila month's revenue, `YYYY-MM`; null is the server's this month.
final adminRevenueProvider = FutureProvider.autoDispose
    .family<RevenueMonth, String?>(
      (ref, month) => ref.watch(adminRepositoryProvider).revenue(month: month),
      retry: apiRetryPolicy,
    );
