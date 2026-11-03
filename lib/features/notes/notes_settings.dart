import 'dart:async';

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/experimental/persist.dart';
import 'package:kover/features/notes/notes_page.dart';
import 'package:kover/features/notes/notes_webhook.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/riverpod/repository/secure_storage.dart';

const notesWebhookKey = 'notes_webhook_v1';

class NotesSettings extends ConsumerWidget {
  const NotesSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.note_alt_outlined),
            title: Text(l.notesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const NotesPage())),
          ),
          ListTile(
            leading: const Icon(Icons.webhook),
            title: Text(l.notesWebhook),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _WebhookEditor(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebhookEditor extends ConsumerStatefulWidget {
  const _WebhookEditor();
  @override
  ConsumerState<_WebhookEditor> createState() => _WebhookEditorState();
}

class _WebhookEditorState extends ConsumerState<_WebhookEditor> {
  final url = TextEditingController();
  final token = TextEditingController();
  bool loading = true;
  bool saving = false;
  bool failed = false;
  bool invalid = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(secureStorageProvider).read(notesWebhookKey);
      if (!mounted) return;
      if (data != null) {
        final config = jsonDecode(data.data) as Map<String, dynamic>;
        url.text = config['url'] as String;
        token.text = config['token'] as String;
      }
      setState(() {
        loading = false;
        failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(l.notesWebhook),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.notesWebhookHint),
                if (loading && !failed) const LinearProgressIndicator(),
                TextField(
                  controller: url,
                  enabled: !loading && !saving,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l.notesUrl,
                    errorText: invalid ? l.notesInvalidUrl : null,
                  ),
                ),
                TextField(
                  controller: token,
                  enabled: !loading && !saving,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: l.notesToken),
                ),
                if (failed) Text(l.notesError),
                if (loading && failed)
                  TextButton(onPressed: _load, child: Text(l.notesRetry)),
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
            onPressed: loading || saving
                ? null
                : () async {
                    try {
                      if (url.text.trim().isNotEmpty) webhookUri(url.text);
                      if (token.text.contains('\n') ||
                          token.text.contains('\r')) {
                        throw const FormatException();
                      }
                    } on FormatException {
                      setState(() => invalid = true);
                      return;
                    }
                    setState(() {
                      saving = true;
                      invalid = false;
                      failed = false;
                    });
                    try {
                      final storage = ref.read(secureStorageProvider);
                      if (url.text.trim().isEmpty) {
                        await storage.delete(notesWebhookKey);
                      } else {
                        await storage.write(
                          notesWebhookKey,
                          jsonEncode({
                            'url': url.text.trim(),
                            'token': token.text.trim(),
                          }),
                          const StorageOptions(
                            cacheTime: StorageCacheTime.unsafe_forever,
                          ),
                        );
                      }
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
            child: Text(l.notesSave),
          ),
        ],
      ),
    );
  }
}
