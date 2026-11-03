import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kover/features/notes/book_note.dart';

Uri webhookUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const FormatException(
      'Use an HTTPS URL without user info or fragment',
    );
  }
  return uri;
}

/// No redirects: a webhook URL may contain a secret. No automatic retries:
/// receivers should use the stable event ID to deduplicate manual retries.
Future<void> sendNoteWebhook({
  required http.Client client,
  required Uri url,
  required BookNote note,
  String token = '',
}) async {
  webhookUri(url.toString());
  if (token.contains('\n') || token.contains('\r')) {
    throw const FormatException('Invalid token');
  }
  final eventId = '${note.id}:${note.updatedAt.toUtc().toIso8601String()}';
  final request = http.Request('POST', url)
    ..followRedirects = false
    ..headers.addAll({
      'Content-Type': 'application/json; charset=utf-8',
      'Idempotency-Key': eventId,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    })
    ..body = jsonEncode({
      'version': 1,
      'event': 'note.exported',
      'eventId': eventId,
      'note': note.toJson(),
    });
  final response = await client
      .send(request)
      .timeout(const Duration(seconds: 20));
  // Do not retain or display server bodies, which may contain secrets.
  await response.stream.drain<void>().timeout(const Duration(seconds: 20));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('HTTP ${response.statusCode}');
  }
}
