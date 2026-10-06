import 'package:html/parser.dart' as html;

String plainHtml(String value) => html.parseFragment(value).text ?? '';

String _string(Map<String, dynamic> row, String key, {bool required = false}) {
  final value = row[key];
  if (value == null && !required) return '';
  if (value is! String && value is! num) {
    throw FormatException('Invalid $key');
  }
  final result = value.toString();
  if (required && result.trim().isEmpty) throw FormatException('Empty $key');
  return result;
}

class LibraryCategory {
  const LibraryCategory({
    required this.id,
    required this.name,
    this.image = '',
    this.author = '',
  });
  final String id;
  final String name;
  final String image;
  final String author;

  factory LibraryCategory.fromJson(Map<String, dynamic> row) => LibraryCategory(
    id: _string(row, 'cid', required: true),
    name: _string(row, 'category_name', required: true),
    image: _string(row, 'category_image'),
    author: _string(row, 'author'),
  );

  Map<String, Object> toJson() => {
    'cid': id,
    'category_name': name,
    'category_image': image,
    'author': author,
  };
}

class LibraryArticle {
  const LibraryArticle({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.htmlBody,
    this.subtitle = '',
    this.createdAt,
    this.updatedAt,
  });
  final String id;
  final String categoryId;
  final String title;
  // In the existing CMS news_date is the subtitle, not a date.
  final String subtitle;
  final String htmlBody;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  String get searchableText => plainHtml('$title\n$subtitle\n$htmlBody');

  factory LibraryArticle.fromJson(Map<String, dynamic> row) => LibraryArticle(
    id: _string(row, 'nid', required: true),
    categoryId: _string(row, 'cat_id', required: true),
    title: _string(row, 'news_heading', required: true),
    subtitle: _string(row, 'news_date'),
    htmlBody: _string(row, 'news_description', required: true),
    createdAt: DateTime.tryParse(_string(row, 'created_at')),
    updatedAt: DateTime.tryParse(_string(row, 'updated_at')),
  );

  Map<String, Object> toJson() => {
    'nid': id,
    'cat_id': categoryId,
    'news_heading': title,
    'news_date': subtitle,
    'news_description': htmlBody,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}
