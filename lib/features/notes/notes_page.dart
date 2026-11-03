import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kover/features/notes/book_note.dart';
import 'package:kover/features/notes/note_editor.dart';
import 'package:kover/features/notes/notes_repository.dart';
import 'package:kover/features/notes/notes_settings.dart';
import 'package:kover/features/notes/notes_webhook.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/repository/secure_storage.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';

class NotesPage extends ConsumerStatefulWidget {
  final int? seriesId;
  const NotesPage({super.key, this.seriesId});
  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  String query = '';
  bool favorites = false;
  final sending = <String>{};

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _copy(Iterable<BookNote> notes) async {
    final l = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: exportNotes(notes)));
      _message(l.notesCopied);
    } catch (_) {
      _message(l.notesError);
    }
  }

  Future<void> _send(BookNote note) async {
    final l = AppLocalizations.of(context);
    setState(() => sending.add(note.id));
    final client = http.Client();
    try {
      final saved = await ref.read(secureStorageProvider).read(notesWebhookKey);
      if (saved == null) {
        _message(l.notesWebhookNeeded);
        return;
      }
      final config = jsonDecode(saved.data) as Map<String, dynamic>;
      await sendNoteWebhook(
        client: client,
        url: webhookUri(config['url'] as String),
        note: note,
        token: config['token'] as String,
      );
      _message(l.notesSent);
    } catch (_) {
      _message(l.notesError);
    } finally {
      client.close();
      if (mounted) setState(() => sending.remove(note.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final result = ref.watch(notesProvider);
    final server = Uri.tryParse(
      widget.seriesId == null
          ? ''
          : (ref.watch(credentialsProvider).value?.url ?? ''),
    );
    final source =
        server != null &&
            server.hasAuthority &&
            (server.scheme == 'http' || server.scheme == 'https')
        ? server.origin
        : '';
    final notes =
        (result.value ?? const <BookNote>[])
            .where(
              (n) =>
                  (widget.seriesId == null ||
                      (n.seriesId == widget.seriesId && n.source == source)) &&
                  (!favorites || n.favorite) &&
                  '${n.book} ${n.quote} ${n.body} ${n.tags.join(' ')}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.notesTitle),
        actions: [
          IconButton(
            tooltip: l.notesImport,
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _NotesImportDialog(),
            ),
          ),
          IconButton(
            tooltip: l.notesCopy,
            onPressed: notes.isEmpty ? null : () => _copy(notes),
            icon: const Icon(Icons.copy_all),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: l.notesSearch,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => query = value.trim()),
              ),
            ),
            FilterChip(
              label: Text(l.notesFavorite),
              selected: favorites,
              avatar: const Icon(Icons.star_outline),
              onSelected: (value) => setState(() => favorites = value),
            ),
            Expanded(
              child: result.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.notesError),
                      TextButton(
                        onPressed: () => ref.invalidate(notesProvider),
                        child: Text(l.notesRetry),
                      ),
                    ],
                  ),
                ),
                data: (all) => notes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            all.isEmpty ? l.notesEmpty : l.notesNoMatches,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final n = notes[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    n.book,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  if (n.source.isNotEmpty)
                                    Text(
                                      n.source,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  Text(
                                    '${n.chapterId} · ${n.page + 1} · ${MaterialLocalizations.of(context).formatShortDate(n.createdAt.toLocal())}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  if (n.quote.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color:
                                            noteColors[n.color.clamp(
                                                  0,
                                                  noteColors.length - 1,
                                                )]
                                                .withValues(alpha: .15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: SelectableText(n.quote),
                                    ),
                                  if (n.body.isNotEmpty) SelectableText(n.body),
                                  if (n.tags.isNotEmpty)
                                    Wrap(
                                      spacing: 6,
                                      children: n.tags
                                          .map(
                                            (tag) => ActionChip(
                                              label: Text(tag),
                                              onPressed: () =>
                                                  setState(() => query = tag),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: l.notesFavorite,
                                        icon: Icon(
                                          n.favorite
                                              ? Icons.star
                                              : Icons.star_border,
                                        ),
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(notesProvider.notifier)
                                                .toggleFavorite(n.id);
                                          } catch (_) {
                                            _message(l.notesError);
                                          }
                                        },
                                      ),
                                      IconButton(
                                        tooltip: l.notesEdit,
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () =>
                                            editBookNote(context, n),
                                      ),
                                      IconButton(
                                        tooltip: l.notesCopy,
                                        icon: const Icon(Icons.copy_outlined),
                                        onPressed: () => _copy([n]),
                                      ),
                                      IconButton(
                                        tooltip: l.notesSend,
                                        icon: sending.contains(n.id)
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.send_outlined),
                                        onPressed: sending.contains(n.id)
                                            ? null
                                            : () => _send(n),
                                      ),
                                      IconButton(
                                        tooltip: l.notesRemove,
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          final confirmed =
                                              await showDialog<bool>(
                                                context: context,
                                                builder: (context) =>
                                                    AlertDialog(
                                                      title: Text(
                                                        l.notesDelete,
                                                      ),
                                                      content: Text(
                                                        l.notesDeleteHint,
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                false,
                                                              ),
                                                          child: Text(
                                                            l.notesCancel,
                                                          ),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                true,
                                                              ),
                                                          child: Text(
                                                            l.notesRemove,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              );
                                          if (confirmed == true && mounted) {
                                            try {
                                              await ref
                                                  .read(notesProvider.notifier)
                                                  .delete(n.id);
                                            } catch (_) {
                                              _message(l.notesError);
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesImportDialog extends ConsumerStatefulWidget {
  const _NotesImportDialog();
  @override
  ConsumerState<_NotesImportDialog> createState() => _NotesImportDialogState();
}

class _NotesImportDialogState extends ConsumerState<_NotesImportDialog> {
  final text = TextEditingController();
  bool busy = false;
  bool failed = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(l.notesImport),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.notesImportHint),
                TextField(
                  controller: text,
                  enabled: !busy,
                  minLines: 4,
                  maxLines: 10,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'JSON'),
                ),
                if (failed) Text(l.notesError),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(l.notesCancel),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      failed = false;
                    });
                    try {
                      await ref
                          .read(notesProvider.notifier)
                          .importJson(text.text);
                      if (context.mounted) {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        messenger.showSnackBar(
                          SnackBar(content: Text(l.notesImported)),
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          busy = false;
                          failed = true;
                        });
                      }
                    }
                  },
            child: Text(l.notesImport),
          ),
        ],
      ),
    );
  }
}
