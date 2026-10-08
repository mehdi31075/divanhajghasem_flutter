class ContentPage {
  const ContentPage({
    required this.slug,
    required this.title,
    required this.htmlBody,
    required this.revision,
    required this.updatedAt,
  });

  final String slug;
  final String title;
  final String htmlBody;
  final int revision;
  final DateTime updatedAt;

  factory ContentPage.fromJson(Map<String, dynamic> json) {
    final slug = json['slug'];
    final title = json['title'];
    final body = json['html_body'];
    final revision = json['revision'];
    final date = json['updated_at'];
    if (slug is! String ||
        !const ['first-talk', 'last-talk', 'contact'].contains(slug) ||
        title is! String ||
        title.trim().isEmpty ||
        body is! String ||
        body.trim().isEmpty ||
        revision is! int ||
        revision < 1 ||
        date is! String ||
        DateTime.tryParse(date) == null) {
      throw const FormatException('Invalid content page');
    }
    return ContentPage(
      slug: slug,
      title: title,
      htmlBody: body,
      revision: revision,
      updatedAt: DateTime.parse(date),
    );
  }

  Map<String, Object> toJson() => {
    'slug': slug,
    'title': title,
    'html_body': htmlBody,
    'revision': revision,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
