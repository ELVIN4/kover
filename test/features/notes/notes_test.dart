import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kover/features/notes/notes_page.dart';
import 'package:kover/features/notes/app_icon_settings.dart';
import 'package:flutter/services.dart';
import 'package:kover/features/notes/note_editor.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kover/features/notes/book_note.dart';
import 'package:kover/features/notes/notes_repository.dart';
import 'package:kover/features/notes/notes_webhook.dart';
import 'package:kover/riverpod/repository/storage_repository.dart';

BookNote note(String id) => BookNote(
  id: id,
  seriesId: 12,
  chapterId: 34,
  page: 5,
  book: 'A book',
  quote: 'A quote',
  body: 'Комментарий',
  tags: const ['reading'],
  createdAt: DateTime.utc(2026, 11, 3),
  updatedAt: DateTime.utc(2026, 11, 3),
);

final class MemoryStorage extends Storage<String, String> {
  final entries = <String, PersistedData<String>>{};
  bool failNextWrite = false;

  @override
  Future<PersistedData<String>?> read(String key) async => entries[key];
  @override
  Future<void> write(String key, String value, StorageOptions options) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('disk full');
    }
    entries[key] = PersistedData(value);
  }

  @override
  Future<void> delete(String key) async {
    entries.remove(key);
  }

  @override
  Future<void> deleteOutOfDate() async {}
}

Widget notesApp(
  MemoryStorage storage,
  Widget child, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [storageProvider.overrideWith((ref) async => storage)],
  child: MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: child,
  ),
);

void main() {
  testWidgets(
    'Russian notes use the same Material UI localization delegates as the app',
    (tester) async {
      final storage = MemoryStorage();
      storage.entries[Notes.storageKey] = PersistedData(
        exportNotes([note('1')]),
      );
      await tester.pumpWidget(
        notesApp(storage, const NotesPage(), locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Заметки к книгам'), findsOneWidget);
      expect(find.text('Избранное'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android icon picker reads and changes the native launcher selection',
    (tester) async {
      const channel = MethodChannel('kover/app_icon');
      String icon = 'default';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getIcon') return icon;
            if (call.method == 'setIcon') {
              icon = call.arguments as String;
              return null;
            }
            throw PlatformException(code: 'unexpected');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        notesApp(MemoryStorage(), const Scaffold(body: AppIconSettings())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ocean'));
      await tester.pumpAndSettle();
      expect(icon, 'blue');
      expect(
        tester
            .widget<ChoiceChip>(
              find.ancestor(
                of: find.text('Ocean'),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('saved notes render and search filters without losing data', (
    tester,
  ) async {
    final storage = MemoryStorage();
    storage.entries[Notes.storageKey] = PersistedData(exportNotes([note('1')]));
    await tester.pumpWidget(notesApp(storage, const NotesPage()));
    await tester.pumpAndSettle();
    expect(find.text('A quote'), findsOneWidget);
    expect(find.text('Комментарий'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'no-match');
    await tester.pumpAndSettle();
    expect(find.text('No matching notes'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'reading');
    await tester.pumpAndSettle();
    expect(find.text('A quote'), findsOneWidget);
    expect(parseNotesExport(storage.entries[Notes.storageKey]!.data).length, 1);
  });

  testWidgets(
    'empty manual note cannot save and editor persists entered comment',
    (tester) async {
      final storage = MemoryStorage();
      final blank = BookNote(
        id: 'manual',
        seriesId: 1,
        chapterId: 2,
        page: 0,
        book: 'Manual book',
        quote: '',
        body: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        notesApp(
          storage,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => editBookNote(context, blank),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField).first, 'Remember this');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = parseNotesExport(storage.entries[Notes.storageKey]!.data)
          .single;
      expect(saved.body, 'Remember this');
      expect(saved.quote, isEmpty);
    },
  );

  test('JSON preserves Unicode, source reference, tags and timestamps', () {
    final original = note('1').edit(color: 2, favorite: true);
    final restored = BookNote.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), original.toJson());
    expect(restored.edit(body: 'Changed').createdAt, original.createdAt);
    expect(restored.edit(body: 'Changed').quote, original.quote);
  });

  test(
    'concurrent writes persist both notes, survive reload and delete one',
    () async {
      final storage = MemoryStorage();
      var container = ProviderContainer(
        overrides: [storageProvider.overrideWith((ref) async => storage)],
      );
      await container.read(notesProvider.future);
      await Future.wait([
        container.read(notesProvider.notifier).save(note('1')),
        container.read(notesProvider.notifier).save(note('2')),
      ]);
      expect(
        container.read(notesProvider).requireValue.map((n) => n.id).toSet(),
        {'1', '2'},
      );
      container.dispose();
      container = ProviderContainer(
        overrides: [storageProvider.overrideWith((ref) async => storage)],
      );
      addTearDown(container.dispose);
      expect((await container.read(notesProvider.future)).length, 2);
      await container.read(notesProvider.notifier).delete('1');
      expect(container.read(notesProvider).requireValue.single.id, '2');
    },
  );

  test(
    'failed persistence keeps saved state and does not poison later writes',
    () async {
      final storage = MemoryStorage();
      final container = ProviderContainer(
        overrides: [storageProvider.overrideWith((ref) async => storage)],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      await container.read(notesProvider.notifier).save(note('1'));
      storage.failNextWrite = true;
      await expectLater(
        container.read(notesProvider.notifier).delete('1'),
        throwsStateError,
      );
      expect(container.read(notesProvider).requireValue.single.id, '1');
      await container.read(notesProvider.notifier).save(note('2'));
      expect(container.read(notesProvider).requireValue.length, 2);
    },
  );

  test('unsupported saved format fails instead of overwriting notes', () async {
    final storage = MemoryStorage();
    storage.entries[Notes.storageKey] = const PersistedData(
      '{"version":2,"notes":[]}',
    );
    final container = ProviderContainer(
      overrides: [storageProvider.overrideWith((ref) async => storage)],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(notesProvider.future),
      throwsFormatException,
    );
    await expectLater(
      container.read(notesProvider.notifier).save(note('1')),
      throwsFormatException,
    );
    expect(storage.entries[Notes.storageKey]!.data, '{"version":2,"notes":[]}');
  });

  test('webhook validates scheme and keeps redirects disabled', () async {
    for (final invalid in [
      'http://example.com',
      'https://user:secret@example.com',
      'https://example.com/#secret',
      'not a URL',
    ]) {
      expect(() => webhookUri(invalid), throwsFormatException);
    }
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.headers['Idempotency-Key'], startsWith('1:'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['event'], 'note.exported');
      expect(body['note'], note('1').toJson());
      return http.Response('', 204);
    });
    addTearDown(client.close);
    await sendNoteWebhook(
      client: client,
      url: webhookUri('https://example.com/hook'),
      note: note('1'),
      token: 'test-token',
    );
    expect(calls, 1);
  });

  test('non-success and redirect responses fail without retry', () async {
    for (final status in [302, 400, 401, 429, 500]) {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('private response', status);
      });
      await expectLater(
        sendNoteWebhook(
          client: client,
          url: webhookUri('https://example.com/hook'),
          note: note('1'),
        ),
        throwsStateError,
      );
      expect(calls, 1);
      client.close();
    }
  });

  test(
    'import merges newer notes and preserves entries absent from export',
    () async {
      final storage = MemoryStorage();
      final container = ProviderContainer(
        overrides: [storageProvider.overrideWith((ref) async => storage)],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      await container.read(notesProvider.notifier).save(note('1'));
      await container.read(notesProvider.notifier).save(note('2'));
      final changed = note('1').edit(body: 'Imported comment');
      await container
          .read(notesProvider.notifier)
          .importJson(exportNotes([changed, note('3')]));
      final all = container.read(notesProvider).requireValue;
      expect(all.length, 3);
      expect(all.singleWhere((n) => n.id == '1').body, 'Imported comment');
      await container
          .read(notesProvider.notifier)
          .importJson(exportNotes([note('1')]));
      expect(
        container
            .read(notesProvider)
            .requireValue
            .singleWhere((n) => n.id == '1')
            .body,
        'Imported comment',
      );
    },
  );

  test(
    'invalid imports and duplicate IDs leave saved collection intact',
    () async {
      final storage = MemoryStorage();
      final container = ProviderContainer(
        overrides: [storageProvider.overrideWith((ref) async => storage)],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      await container.read(notesProvider.notifier).save(note('1'));
      for (final invalid in [
        '{}',
        exportNotes([note('2'), note('2')]),
        exportNotes([note('3').edit(color: 99)]),
      ]) {
        expect(
          () => container.read(notesProvider.notifier).importJson(invalid),
          throwsA(anything),
        );
        expect(container.read(notesProvider).requireValue.single.id, '1');
      }
    },
  );

  test('concurrent favorite toggles use the latest persisted note', () async {
    final storage = MemoryStorage();
    final container = ProviderContainer(
      overrides: [storageProvider.overrideWith((ref) async => storage)],
    );
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    await container.read(notesProvider.notifier).save(note('1'));
    await Future.wait([
      container.read(notesProvider.notifier).toggleFavorite('1'),
      container.read(notesProvider.notifier).toggleFavorite('1'),
    ]);
    expect(container.read(notesProvider).requireValue.single.favorite, isFalse);
  });

  test('JSON export contains exactly the supplied selection', () {
    final exported =
        jsonDecode(exportNotes([note('2')])) as Map<String, dynamic>;
    expect(exported['version'], 1);
    expect((exported['notes'] as List).single['id'], '2');
  });
}
