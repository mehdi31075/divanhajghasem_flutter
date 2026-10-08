import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/library.dart';
import '../domain/content_page.dart';

class LegacyApi {
  LegacyApi({
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 45),
  }) : client = client ?? http.Client(),
       endpoint =
           endpoint ??
           Uri.parse(
             const String.fromEnvironment(
               'DIVAN_API_URL',
               defaultValue: 'http://divanhajghasem.ir/api.php',
             ),
           );

  final http.Client client;
  final Uri endpoint;
  final Duration timeout;

  Future<List<Map<String, dynamic>>> _get(Map<String, String> query) async {
    final response = await client
        .get(
          endpoint.replace(
            queryParameters: {...endpoint.queryParameters, ...query},
          ),
          headers: {'cache-control': 'no-cache'},
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', endpoint);
    }
    // The old PHP endpoint does not consistently send a JSON charset header.
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes).replaceFirst('\uFEFF', '').trim(),
    );
    // api.php initializes an empty PHP array: it emits [] for zero records.
    if (decoded is List && decoded.isEmpty) return [];
    if (decoded is! Map<String, dynamic> ||
        decoded['AndroidEbookApp'] is! List) {
      throw const FormatException('Unexpected API response');
    }
    return (decoded['AndroidEbookApp'] as List).map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid record');
      }
      return row;
    }).toList();
  }

  Future<List<LibraryCategory>> categories() async =>
      (await _get({})).map(LibraryCategory.fromJson).toList();

  Future<List<ContentPage>> pages() async {
    final url = endpoint.resolve('pages.php');
    final response = await client
        .get(url, headers: {'cache-control': 'no-cache'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', url);
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes).replaceFirst('\uFEFF', '').trim(),
    );
    if (decoded is! Map<String, dynamic> || decoded['pages'] is! List) {
      throw const FormatException('Unexpected content pages response');
    }
    final pages = (decoded['pages'] as List).map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid content page');
      }
      return ContentPage.fromJson(row);
    }).toList();
    if (pages.length != 3 ||
        pages.map((page) => page.slug).toSet().length != 3) {
      throw const FormatException('Missing or duplicate content pages');
    }
    return pages;
  }

  Future<List<LibraryArticle>> articles(String categoryId) async {
    final rows = (await _get({
      'cat_id': categoryId,
    })).map(LibraryArticle.fromJson).toList();
    if (rows.any((article) => article.categoryId != categoryId)) {
      throw const FormatException('Category mismatch');
    }
    return rows;
  }

  Future<LibraryArticle> article(String id) async {
    final result = await findArticle(id);
    if (result == null) throw const FormatException('Article not found');
    return result;
  }

  Future<LibraryArticle?> findArticle(String id) async {
    final rows = (await _get({
      'nid': id,
    })).map(LibraryArticle.fromJson).toList();
    if (rows.isEmpty) return null;
    if (rows.length != 1 || rows.single.id != id) {
      throw const FormatException('Article not found');
    }
    return rows.single;
  }

  Uri? categoryImage(LibraryCategory category) {
    final path = category.image.trim();
    if (path.isEmpty) return null;
    final parsed = Uri.tryParse(path);
    final uri = parsed?.isAbsolute == true
        ? parsed!
        : endpoint.resolve(
            path.startsWith('/') || path.startsWith('upload/')
                ? path
                : 'upload/category/$path',
          );
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }

  void close() => client.close();
}
