import 'package:flutter_riverpod/flutter_riverpod.dart';

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
