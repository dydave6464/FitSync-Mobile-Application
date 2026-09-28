import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/activity/data/step_permission.dart';

DeviceStepPermission _perm({
  required InMemorySecureStore store,
  bool granted = false,
  bool grantOnRequest = false,
  List<String>? log,
}) {
  var isGranted = granted;
  return DeviceStepPermission(
    store: store,
    isGranted: () async => isGranted,
    requestGrant: () async {
      log?.add('request');
      isGranted = grantOnRequest;
      return grantOnRequest;
    },
    openSettings: () async => log?.add('settings'),
  );
}

void main() {
  test('never asked is notAsked', () async {
    expect(await _perm(store: InMemorySecureStore()).status(), StepAccess.notAsked);
  });

  test('granted by the OS is granted, asked or not', () async {
    expect(await _perm(store: InMemorySecureStore(), granted: true).status(), StepAccess.granted);
  });

  test('asked and not granted is refused, and stays so', () async {
    final store = InMemorySecureStore();
    final p = _perm(store: store);
    expect(await p.request(), StepAccess.refused);
    expect(await _perm(store: store).status(), StepAccess.refused);
  });

  test('a grant on request is granted', () async {
    final log = <String>[];
    final p = _perm(store: InMemorySecureStore(), grantOnRequest: true, log: log);
    expect(await p.request(), StepAccess.granted);
    expect(log, ['request']);
  });

  test('NoStepPermission never grants', () async {
    const p = NoStepPermission();
    expect(await p.status(), StepAccess.notAsked);
    expect(await p.request(), StepAccess.refused);
  });
}
