import 'dart:math';

/// A local annotation. Page numbers are zero based; EPUB locations are sections.
class BookNote {
  final String id;
  final int seriesId;
  final int chapterId;
  final int page;
  final String book;
  final String source;
  final String quote;
  final String body;
  final List<String> tags;
  final int color;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookNote({
    required this.id,
    required this.seriesId,
    required this.chapterId,
    required this.page,
    required this.book,
    required this.quote,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.source = '',
    this.tags = const [],
    this.color = 0,
    this.favorite = false,
  });

  static final _random = Random.secure();

  static String newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  BookNote edit({
    String? body,
    List<String>? tags,
    int? color,
    bool? favorite,
  }) => BookNote(
    id: id,
    seriesId: seriesId,
    chapterId: chapterId,
    page: page,
    book: book,
    source: source,
    quote: quote,
    body: body ?? this.body,
    tags: List.unmodifiable(tags ?? this.tags),
    color: color ?? this.color,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'seriesId': seriesId,
    'chapterId': chapterId,
    'page': page,
    'book': book,
    'source': source,
    'quote': quote,
    'body': body,
    'tags': tags,
    'color': color,
    'favorite': favorite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory BookNote.fromJson(Map<String, dynamic> json) => BookNote(
    id: json['id'] as String,
    seriesId: json['seriesId'] as int,
    chapterId: json['chapterId'] as int,
    page: json['page'] as int,
    source: json['source'] as String? ?? '',
    book: json['book'] as String,
    quote: json['quote'] as String,
    body: json['body'] as String,
    tags: List<String>.unmodifiable(json['tags'] as List),
    color: json['color'] as int,
    favorite: json['favorite'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
