import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:kover/features/notes/book_note.dart';
import 'package:kover/riverpod/repository/storage_repository.dart';

final notesProvider = AsyncNotifierProvider<Notes, List<BookNote>>(
  Notes.new,
  retry: (_, _) => null,
);

class Notes extends AsyncNotifier<List<BookNote>> {
  static const storageKey = 'book_notes_v1';
  Future<void> _pending = Future.value();

  @override
  Future<List<BookNote>> build() async {
    final storage = await ref.watch(storageProvider.future);
    final saved = await storage.read(storageKey);
    if (saved == null) return const [];
    final json = jsonDecode(saved.data) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown notes version');
    }
    return List.unmodifiable(
      (json['notes'] as List).map(
        (entry) => BookNote.fromJson(entry as Map<String, dynamic>),
      ),
    );
  }

  /// Serialize writes and publish only after storage confirms persistence.
  Future<void> _change(List<BookNote> Function(List<BookNote>) update) {
    final operation = _pending.then((_) async {
      final current = await future;
      final next = update(current);
      final storage = await ref.read(storageProvider.future);
      final encoded = exportNotes(next);
      parseNotesExport(encoded);
      await storage.write(
        storageKey,
        encoded,
        const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever),
      );
      state = AsyncData(List.unmodifiable(next));
    });
    _pending = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> save(BookNote note) {
    parseNotesExport(exportNotes([note]));
    return _change(
      (notes) => [note, ...notes.where((entry) => entry.id != note.id)],
    );
  }

  Future<void> importJson(String value) {
    final incoming = parseNotesExport(value);
    return _change((notes) {
      final merged = {for (final note in notes) note.id: note};
      for (final note in incoming) {
        final current = merged[note.id];
        if (current == null || note.updatedAt.isAfter(current.updatedAt)) {
          merged[note.id] = note;
        }
      }
      return merged.values.toList();
    });
  }

  Future<void> toggleFavorite(String id) => _change(
    (notes) => [
      for (final note in notes)
        if (note.id == id) note.edit(favorite: !note.favorite) else note,
    ],
  );

  Future<void> delete(String id) =>
      _change((notes) => notes.where((note) => note.id != id).toList());
}

String exportNotes(Iterable<BookNote> notes) => const JsonEncoder.withIndent(
  '  ',
).convert({'version': 1, 'notes': notes.map((n) => n.toJson()).toList()});

/// Validate the whole import before allowing any change to the saved collection.
List<BookNote> parseNotesExport(String value) {
  if (value.length > 5000000) throw const FormatException('Export too large');
  final json = jsonDecode(value) as Map<String, dynamic>;
  if (json['version'] != 1) {
    throw const FormatException('Unknown notes version');
  }
  final entries = json['notes'] as List;
  if (entries.length > 10000) throw const FormatException('Too many notes');
  final notes = entries
      .map((entry) => BookNote.fromJson(entry as Map<String, dynamic>))
      .toList();
  final ids = <String>{};
  for (final note in notes) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(note.id) ||
        !ids.add(note.id) ||
        note.seriesId < 0 ||
        note.chapterId < 0 ||
        note.page < 0 ||
        note.color < 0 ||
        note.color > 3 ||
        note.tags.length > 32 ||
        note.tags.any((tag) => tag.length > 100) ||
        note.body.length > 20000 ||
        note.quote.length > 200000 ||
        (note.body.trim().isEmpty && note.quote.trim().isEmpty)) {
      throw const FormatException('Invalid note');
    }
  }
  return notes;
}
