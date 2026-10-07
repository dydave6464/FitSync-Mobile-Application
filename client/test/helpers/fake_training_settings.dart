import 'package:fitsync/features/sessions/data/training_settings_repository.dart';

/// Answers the saved rest time without a server. Records every write, and
/// fails them with [writeError] when a test sets one.
class FakeTrainingSettings implements TrainingSettingsRepository {
  FakeTrainingSettings([this.stored = 90]);

  int stored;
  final List<int> writes = [];
  Object? writeError;

  @override
  Future<int> restSeconds() async => stored;

  @override
  Future<int> setRestSeconds(int seconds) async {
    writes.add(seconds);
    if (writeError != null) throw writeError!;
    return stored = seconds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
