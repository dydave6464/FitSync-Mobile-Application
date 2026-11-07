import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';

import 'helpers/fake_admin_repository.dart';

List<AdminUserRow> _rows(int count, {int from = 0, bool suspended = false}) => [
  for (var i = from; i < from + count; i++)
    sampleRow(id: 1000 - i, fullName: 'Trainee $i', suspended: suspended),
];

void main() {
  test('a page asked for while the list refreshes cannot overwrite it',
      () async {
    // The first load answers at once; the refresh after a suspension and
    // any next page wait until the test lets them through.
    final refresh = Completer<AdminUsersPage>();
    final nextPage = Completer<AdminUsersPage>();
    var firstLoad = true;
    final repo = FakeAdminRepository(
      users: (_, _, page) {
        if (page > 1) return nextPage.future;
        if (firstLoad) {
          firstLoad = false;
          return Future.value(usersPage(_rows(30), total: 40));
        }
        return refresh.future;
      },
    );
    final container = ProviderContainer(
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.listen(adminUsersProvider, (_, _) {});
    await container.read(adminUsersProvider.future);

    // A trainee is suspended and the list is refreshed; the refresh is slow.
    container.invalidate(adminUsersProvider);
    expect(container.read(adminUsersProvider).isLoading, isTrue);

    // A scroll near the end asks for more while the refresh is pending.
    // Not awaited: on the bug it waits on the next page, released below.
    final more = container.read(adminUsersProvider.notifier).loadMore();
    await pumpEventQueue();
    expect(repo.usersCalls.map((c) => c.page), [1, 1]);

    // The refresh lands with the trainee now suspended.
    refresh.complete(usersPage(_rows(30, suspended: true), total: 40));
    await container.read(adminUsersProvider.future);
    if (!nextPage.isCompleted) {
      nextPage.complete(usersPage(_rows(10, from: 30), page: 2, total: 40));
    }
    await more;
    await pumpEventQueue();

    final state = container.read(adminUsersProvider).requireValue;
    expect(state.items, hasLength(30));
    expect(state.items.every((r) => r.suspended), isTrue);
    expect(state.page, 1);
  });
}
