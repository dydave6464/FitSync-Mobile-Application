import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/calendar_repository.dart';
import '../domain/calendar.dart';

/// A date range, `YYYY-MM-DD` both ends inclusive.
typedef CalendarSpan = ({String from, String to});

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepository(ref.watch(apiClientProvider)),
);

/// One range of the Schedule -- the grid's six weeks, or the coming week.
/// autoDispose: it lives only while the Schedule is open, so it needs no
/// place on sign-out's list of per-user caches.
final calendarProvider = FutureProvider.autoDispose
    .family<CalendarRange, CalendarSpan>(
      (ref, span) =>
          ref.watch(calendarRepositoryProvider).range(span.from, span.to),
      retry: apiRetryPolicy,
    );
