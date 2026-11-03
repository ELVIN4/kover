# Reading notes

In an EPUB or a PDF with selectable text, select a passage and choose **Add note**.
PDF copy restrictions are respected; image-only books and scanned PDFs require a
manual note from the reader's notes menu (no OCR is included).

The editor preserves the quotation and book reference, and lets you add a comment,
comma-separated tags and one of four colors. Colors decorate the saved quotation;
they do not currently redraw persistent highlights over the book's pages. EPUB
positions identify a section, not a stable rendered page after font/layout changes.

Open a book's notes from the reader controls, or all notes from Settings → Book
notes. Search includes quotations, comments, book names and tags. You can edit,
mark favorites, copy a note or the filtered list as versioned JSON, and delete with
confirmation. Deletion only affects the local copy. Notes are local to this app's
database and are not synchronized to Kavita. Clearing app data removes them; keep
JSON exports for your own records. Use Import JSON on the notes screen to restore
an export. Imports validate the entire document before writing; matching IDs keep
the newer version, and notes missing from the export remain untouched.

## Webhook

Settings → Notes webhook accepts an HTTPS URL and optional Bearer token. The URL
and token use the app's existing secure-storage backend. An empty URL removes the
configuration. Tokens and response bodies are not shown in error messages.

Sending is always explicit, per note. The receiver gets a UTF-8 JSON POST:

```json
{
  "version": 1,
  "event": "note.exported",
  "eventId": "<note-id>:<updated-at-UTC>",
  "note": {
    "id": "<note-id>",
    "seriesId": 12,
    "chapterId": 34,
    "page": 5,
    "source": "https://books.example.com",
    "book": "Example book",
    "quote": "Selected passage",
    "body": "My comment",
    "tags": ["research"],
    "color": 0,
    "favorite": false,
    "createdAt": "2026-11-03T12:00:00.000Z",
    "updatedAt": "2026-11-03T12:00:00.000Z"
  }
}
```

The page/section index is zero based. `source` contains the Kavita server's origin,
without credentials or URL query parameters. Colors are 0=yellow, 1=green,
2=blue, 3=pink. The `Idempotency-Key` header equals `eventId`; receivers should
store it to deduplicate retries. Any 2xx response is accepted. Redirects, non-2xx
responses and timeouts fail without modifying the saved note. There are no
background sends or automatic retries. A timed-out request may already have been
processed by the receiver. Web deployments also require receiver CORS support.

## Android icons

Settings → App icon switches between Original, Ocean and Amber using Android
launcher aliases. The selection survives process restarts. Some launchers refresh
icons with a delay. This feature applies to Android only.

## Validation and release

Use the Flutter version in `.fvmrc` (3.47.9) and the existing checkout:

```sh
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
dart format lib/features/notes test/features/notes lib/pages/reader/epub_reader/epub_reader.dart lib/pages/reader/pdf_reader/pdf_reader.dart lib/pages/reader/overlay/reader_controls.dart lib/pages/settings/settings_page.dart
flutter analyze
flutter test
flutter build apk --release
```

Release builds use the repository's existing keystore environment bindings
(`KEYSTORE_PATH`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`). Do not change
an existing application's signing identity. Its GitHub release workflow additionally
expects the corresponding `GOOGLE_PLAY_*` signing secrets.

Run Flutter tests and release builds sequentially. Both regenerate native plugin
registration; running tests or `flutter pub get` during an APK build can reintroduce
dev-only plugins into the release registrant.

Before release, test on an Android device: EPUB/PDF selection, reopening saved
notes after killing the process, search/tags/favorites/edit/delete, webhook success
and failure, and switching each icon followed by reopening the app from the
launcher. Automated tests cover serialization, concurrent persistence, write
failure recovery, export selection and webhook HTTP behavior. A test source file
alone does not establish that these checks have passed.
