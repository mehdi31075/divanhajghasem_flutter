import 'dart:convert';
import 'dart:math';
import 'library.dart';

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.categoryId,
    required this.updatedAt,
    this.revision = 1,
    this.favorite = false,
    this.deleted = false,
    this.subtitle = '',
    this.bodyIsHtml = false,
    this.serverBase,
    this.serverSource,
    this.richTextDelta,
  });

  factory Note.empty() => Note(
    id: newId(),
    title: '',
    body: '',
    categoryId: null,
    updatedAt: DateTime.now(),
  );

  final String id;
  final String title;
  final String body;
  final String? categoryId;
  final DateTime updatedAt;
  final int revision;
  final bool favorite;
  final bool deleted;
  final String subtitle;
  final bool bodyIsHtml;
  final String? serverBase;
  final String? serverSource;
  final String? richTextDelta;
  LibraryArticle? get original => serverBase == null
      ? null
      : LibraryArticle.fromJson(
          jsonDecode(serverBase!) as Map<String, dynamic>,
        );
  String get htmlBody => bodyIsHtml
      ? body
      : '<p>${const HtmlEscape().convert(body).replaceAll('\n', '<br>')}</p>';
  String get displayTitle => title.trim().isEmpty ? 'یادداشت بی‌عنوان' : title;

  Note copyWith({
    String? title,
    String? body,
    String? categoryId,
    bool clearCategory = false,
    DateTime? updatedAt,
    int? revision,
    bool? favorite,
    bool? deleted,
    String? subtitle,
    bool? bodyIsHtml,
    String? serverBase,
    String? serverSource,
    String? richTextDelta,
    bool clearRichText = false,
  }) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
    favorite: favorite ?? this.favorite,
    deleted: deleted ?? this.deleted,
    subtitle: subtitle ?? this.subtitle,
    bodyIsHtml: bodyIsHtml ?? this.bodyIsHtml,
    serverBase: serverBase ?? this.serverBase,
    serverSource: serverSource ?? this.serverSource,
    richTextDelta: clearRichText
        ? null
        : richTextDelta ??
              (body != null && body != this.body ? null : this.richTextDelta),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'category_id': categoryId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'revision': revision,
    'favorite': favorite ? 1 : 0,
    'deleted': deleted ? 1 : 0,
    'subtitle': subtitle,
    'body_is_html': bodyIsHtml ? 1 : 0,
    'server_base': serverBase,
    'server_source': serverSource,
    'rich_text_delta': richTextDelta,
  };

  factory Note.fromMap(Map<String, Object?> map) => Note(
    id: map['id']! as String,
    title: map['title']! as String,
    body: map['body']! as String,
    categoryId: map['category_id'] as String?,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
    revision: map['revision']! as int,
    favorite: map['favorite'] == 1,
    deleted: map['deleted'] == 1,
    subtitle: map['subtitle'] as String? ?? '',
    bodyIsHtml: map['body_is_html'] == 1,
    serverBase: map['server_base'] as String?,
    serverSource: map['server_source'] as String?,
    richTextDelta: map['rich_text_delta'] as String?,
  );
}

class NoteCategory {
  const NoteCategory(this.id, this.name);
  final String id;
  final String name;
}

class NoteVersion {
  const NoteVersion({
    required this.id,
    required this.noteId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.snapshot,
  });
  final int id;
  final String noteId;
  final String title;
  final String body;
  final DateTime createdAt;
  final Note? snapshot;
}
