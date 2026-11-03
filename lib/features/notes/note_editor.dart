import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/features/notes/book_note.dart';
import 'package:kover/features/notes/notes_repository.dart';
import 'package:kover/generated/l10n/app_localizations.dart';

const noteColors = [Colors.amber, Colors.green, Colors.blue, Colors.pink];

Future<void> editBookNote(BuildContext context, BookNote note) =>
    showDialog<void>(
      context: context,
      builder: (_) => _NoteEditor(note: note),
    );

class _NoteEditor extends ConsumerStatefulWidget {
  final BookNote note;
  const _NoteEditor({required this.note});

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  late final body = TextEditingController(text: widget.note.body);
  late final tags = TextEditingController(text: widget.note.tags.join(', '));
  late int color = widget.note.color.clamp(0, noteColors.length - 1);
  bool saving = false;
  bool failed = false;

  @override
  void dispose() {
    body.dispose();
    tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final names = [l.notesYellow, l.notesGreen, l.notesBlue, l.notesPink];
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l.notesEdit),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.note.book,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (widget.note.quote.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: noteColors[color].withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(color: noteColors[color], width: 4),
                      ),
                    ),
                    child: SelectableText(widget.note.quote),
                  ),
                TextField(
                  controller: body,
                  autofocus: true,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 20000,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: l.notesBody),
                ),
                TextField(
                  controller: tags,
                  enabled: !saving,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: l.notesTags),
                ),
                const SizedBox(height: 12),
                Text(l.notesColor),
                Wrap(
                  spacing: 8,
                  children: List.generate(
                    noteColors.length,
                    (i) => ChoiceChip(
                      label: Text(names[i]),
                      selected: color == i,
                      avatar: CircleAvatar(
                        backgroundColor: noteColors[i],
                        radius: 6,
                      ),
                      onSelected: saving
                          ? null
                          : (_) => setState(() => color = i),
                    ),
                  ),
                ),
                if (failed)
                  Text(
                    l.notesError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: Text(l.notesCancel),
          ),
          FilledButton(
            onPressed:
                saving ||
                    (body.text.trim().isEmpty &&
                        widget.note.quote.trim().isEmpty)
                ? null
                : () async {
                    setState(() {
                      saving = true;
                      failed = false;
                    });
                    try {
                      await ref
                          .read(notesProvider.notifier)
                          .save(
                            widget.note.edit(
                              body: body.text.trim(),
                              color: color,
                              tags: tags.text
                                  .split(',')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toSet()
                                  .toList(),
                            ),
                          );
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          failed = true;
                        });
                      }
                    }
                  },
            child: Text(saving ? '…' : l.notesSave),
          ),
        ],
      ),
    );
  }
}
