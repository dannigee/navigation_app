import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts clean at generation zero', () async {
    expect(await ConfigMutationNotifier.instance.generation(), 0);
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);
  });

  test('notify increments the generation and makes it dirty', () async {
    await ConfigMutationNotifier.instance.notify();
    expect(await ConfigMutationNotifier.instance.generation(), 1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);
  });

  test('markSynced clears dirty for that generation only', () async {
    await ConfigMutationNotifier.instance.notify();
    await ConfigMutationNotifier.instance.markSynced(1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isFalse);

    await ConfigMutationNotifier.instance.notify();
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);
  });

  test('markSynced for a stale generation does not clear a newer edit',
      () async {
    await ConfigMutationNotifier.instance.notify(); // 1
    await ConfigMutationNotifier.instance.notify(); // 2
    await ConfigMutationNotifier.instance.markSynced(1);
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'an edit made during an in-flight push must stay pending');
  });

  test('dirty state is persisted, so it survives a restart', () async {
    await ConfigMutationNotifier.instance.notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'an in-memory debounce dies with the app; intent must not');
  });

  test('emits the new generation on the stream', () async {
    final seen = <int>[];
    final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);
    await ConfigMutationNotifier.instance.notify();
    await ConfigMutationNotifier.instance.notify();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [1, 2]);
  });

  group('suspendWhile', () {
    test('neither bumps the generation nor emits, so a restore is not an edit',
        () async {
      final seen = <int>[];
      final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);

      await ConfigMutationNotifier.instance.suspendWhile(() async {
        await ConfigMutationNotifier.instance.notify();
        await ConfigMutationNotifier.instance.notify();
      });

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(await ConfigMutationNotifier.instance.generation(), 0);
      expect(seen, isEmpty);
    });

    test('resumes notifying afterwards, even if the body threw', () async {
      await expectLater(
        ConfigMutationNotifier.instance
            .suspendWhile(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      await ConfigMutationNotifier.instance.notify();
      expect(await ConfigMutationNotifier.instance.generation(), 1,
          reason: 'a failed restore must not leave notifications muted');
    });
  });

  group('store wiring', () {
    test('a store write notifies', () async {
      final before = await ConfigMutationNotifier.instance.generation();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Ambo')]);
      expect(await ConfigMutationNotifier.instance.generation(), before + 1,
          reason: 'a store that does not report is never backed up');
    });
  });
}
