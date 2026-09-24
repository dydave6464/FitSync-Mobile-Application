import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/routine/domain/routine.dart';

void main() {
  test(
    'formatWeekdays names days in weekday order, all seven as Every day',
    () {
      expect(formatWeekdays([1, 2, 3, 4, 5, 6, 7]), 'Every day');
      expect(formatWeekdays([7, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(formatWeekdays([2, 4]), 'Tue, Thu');
      expect(formatWeekdays([5, 1, 3]), 'Mon, Wed, Fri');
      expect(formatWeekdays([7]), 'Sun');
    },
  );
}
