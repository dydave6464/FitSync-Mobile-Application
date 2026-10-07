import 'package:fitsync/features/health/data/health_repository.dart';
import 'package:fitsync/features/health/domain/health_answers.dart';

/// Answers the stored health check without a server. Records every write and
/// delete, and fails writes with [writeError] when a test sets one.
class FakeHealthRepository implements HealthRepository {
  FakeHealthRepository({this.stored});

  HealthAnswers? stored;
  final List<HealthAnswers> writes = [];
  int deletes = 0;
  Object? writeError;

  @override
  Future<HealthAnswers?> getHealth() async => stored;

  @override
  Future<HealthAnswers?> setHealth(HealthAnswers answers) async {
    writes.add(answers);
    if (writeError != null) throw writeError!;
    return stored = answers;
  }

  @override
  Future<void> deleteHealth() async {
    deletes += 1;
    stored = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
