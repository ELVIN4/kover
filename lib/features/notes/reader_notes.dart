import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/features/notes/book_note.dart';
import 'package:kover/features/notes/note_editor.dart';
import 'package:kover/features/notes/notes_page.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/providers/reader/reader.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';

Future<void> createReaderNote(
  BuildContext context,
  WidgetRef ref, {
  required int seriesId,
  required int chapterId,
  required int page,
  required int? readingListId,
  String quote = '',
}) async {
  final l = AppLocalizations.of(context);
  try {
    final reader = await ref.read(
      readerProvider(
        seriesId: seriesId,
        chapterId: chapterId,
        readingListId: readingListId,
      ).future,
    );
    if (!context.mounted) return;
    final now = DateTime.now().toUtc();
    final uri = Uri.tryParse(ref.read(credentialsProvider).value?.url ?? '');
    final source =
        uri != null &&
            uri.hasAuthority &&
            (uri.scheme == 'http' || uri.scheme == 'https')
        ? uri.origin
        : '';
    await editBookNote(
      context,
      BookNote(
        id: BookNote.newId(),
        seriesId: seriesId,
        chapterId: chapterId,
        page: page,
        book: reader.series.name,
        source: source,
        quote: quote,
        body: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.notesError)));
    }
  }
}

class ReaderNotesButton extends ConsumerWidget {
  final int seriesId;
  final int chapterId;
  final int? readingListId;
  final int page;
  const ReaderNotesButton({
    super.key,
    required this.seriesId,
    required this.chapterId,
    required this.readingListId,
    required this.page,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: l.notesTitle,
      icon: const Icon(Icons.note_alt_outlined),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'add', child: Text(l.notesAdd)),
        PopupMenuItem(value: 'list', child: Text(l.notesTitle)),
      ],
      onSelected: (value) {
        if (value == 'list') {
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotesPage(seriesId: seriesId),
              ),
            ),
          );
        } else {
          unawaited(
            createReaderNote(
              context,
              ref,
              seriesId: seriesId,
              chapterId: chapterId,
              readingListId: readingListId,
              page: page,
            ),
          );
        }
      },
    );
  }
}
