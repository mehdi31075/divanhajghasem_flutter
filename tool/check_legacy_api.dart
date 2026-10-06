import 'dart:io';
import 'package:hajqasem_app/data/legacy_api.dart';

/// Read-only smoke check against the configured public API.
Future<void> main() async {
  final api = LegacyApi();
  try {
    final categories = await api.categories();
    stdout.writeln('Categories parsed: ${categories.length}');
    if (categories.isEmpty) throw StateError('No categories to check');
    final articles = await api.articles(categories.first.id);
    stdout.writeln(
      'Articles parsed in category ${categories.first.id}: ${articles.length}',
    );
    if (articles.isEmpty) throw StateError('No articles to check');
    final detail = await api.article(articles.first.id);
    if (detail.htmlBody != articles.first.htmlBody ||
        detail.subtitle != articles.first.subtitle) {
      throw StateError('List/detail content differs');
    }
    stdout.writeln(
      'Detail ${detail.id}: title, subtitle and HTML match the category response.',
    );
  } finally {
    api.close();
  }
}
