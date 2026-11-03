import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:kover/generated/l10n/app_localizations.dart';

class AppIconSettings extends StatefulWidget {
  const AppIconSettings({super.key});
  @override
  State<AppIconSettings> createState() => _AppIconSettingsState();
}

class _AppIconSettingsState extends State<AppIconSettings> {
  static const channel = MethodChannel('kover/app_icon');
  String? selected;
  bool busy = false;
  bool failed = false;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (supported) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await channel.invokeMethod<String>('getIcon');
      if (mounted) {
        setState(() {
          selected = value ?? 'default';
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supported) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final icons = [
      ('default', l.notesIconDefault, null),
      ('blue', l.notesIconBlue, Colors.blue),
      ('amber', l.notesIconAmber, Colors.amber),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.notesIcon, style: Theme.of(context).textTheme.headlineSmall),
            Text(l.notesIconHint),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: icons
                  .map(
                    (entry) => ChoiceChip(
                      avatar: entry.$3 == null
                          ? Image.asset('assets/icon/icon.png')
                          : CircleAvatar(
                              backgroundColor: entry.$3,
                              child: const Icon(
                                Icons.auto_stories,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                      label: Text(entry.$2),
                      selected: selected == entry.$1,
                      onSelected: busy || selected == null
                          ? null
                          : (_) async {
                              setState(() {
                                busy = true;
                                failed = false;
                              });
                              try {
                                await channel.invokeMethod<void>(
                                  'setIcon',
                                  entry.$1,
                                );
                                if (mounted) {
                                  setState(() => selected = entry.$1);
                                }
                              } catch (_) {
                                if (mounted) setState(() => failed = true);
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                    ),
                  )
                  .toList(),
            ),
            if (failed) Text(l.notesError),
            if (failed && selected == null)
              TextButton(onPressed: _load, child: Text(l.notesRetry)),
          ],
        ),
      ),
    );
  }
}
