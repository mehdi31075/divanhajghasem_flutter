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
               defaultValue: 'http://divanhajghasem.ir/index.php/api.php',
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

  Uri _supportUrl(String action) => endpoint
      .resolve('mobile-api.php')
      .replace(scheme: 'https', queryParameters: {'action': action});

  Future<Map<String, dynamic>> _supportPost(
    String action,
    Map<String, String> fields, {
    String? token,
  }) async {
    final url = _supportUrl(action);
    final headers = <String, String>{'accept': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    final response = await client
        .post(url, headers: headers, body: fields)
        .timeout(timeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const FormatException('پاسخ پشتیبانی معتبر نیست.');
    }
    if (response.statusCode != 200 ||
        decoded is! Map<String, dynamic> ||
        decoded['ok'] != true) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message']
          : null;
      throw Exception(message is String ? message : 'ارسال پیام انجام نشد.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> startSupportOtp(String name, String mobile) =>
      _supportPost('support_start', {'name': name, 'mobile': mobile});

  Future<Map<String, dynamic>> startAccountOtp(String mobile) =>
      _supportPost('user_start', {'mobile': mobile});

  Future<Map<String, dynamic>> verifySupportOtp(
    String challengeId,
    String otp,
  ) =>
      _supportPost('support_verify', {'challenge_id': challengeId, 'otp': otp});

  Future<Map<String, dynamic>> verifyAccountOtp(
    String challengeId,
    String otp, {
    String? name,
  }) {
    final fields = <String, String>{'challenge_id': challengeId, 'otp': otp};
    if (name != null) fields['name'] = name;
    return _supportPost('user_verify', fields);
  }

  Future<Map<String, dynamic>> accountUser(String token) async {
    final url = _supportUrl('user_me');
    final response = await client
        .get(
          url,
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer $token',
          },
        )
        .timeout(timeout);
    final decoded = _decodeMobileResponse(response, 'دریافت حساب انجام نشد.');
    if (decoded['user'] is! Map<String, dynamic>) {
      throw const FormatException('اطلاعات حساب معتبر نیست.');
    }
    return decoded['user'] as Map<String, dynamic>;
  }

  Future<void> logoutAccount(String token) async {
    await _supportPost('user_logout', const {}, token: token);
  }

  Future<int> incrementArticleView(String articleId) async {
    final result = await _supportPost('article_view', {'nid': articleId});
    final views = result['views'];
    if (views is! num) throw const FormatException('تعداد بازدید معتبر نیست.');
    return views.toInt();
  }

  Map<String, dynamic> _decodeMobileResponse(
    http.Response response,
    String fallback,
  ) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw FormatException(fallback);
    }
    if (response.statusCode != 200 ||
        decoded is! Map<String, dynamic> ||
        decoded['ok'] != true) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message']
          : null;
      throw Exception(message is String ? message : fallback);
    }
    return decoded;
  }

  Future<void> submitSupportMessage(
    String token,
    String message, {
    String? ticketId,
  }) async {
    final fields = <String, String>{'message': message};
    if (ticketId != null && ticketId.isNotEmpty) {
      fields['ticket_id'] = ticketId;
    }
    await _supportPost('support_send', fields, token: token);
  }

  Future<void> submitSupportReply(
    String token,
    String ticketId,
    String message,
  ) =>
      submitSupportMessage(token, message, ticketId: ticketId);

  Future<List<Map<String, dynamic>>> supportMessages(String token) async {
    final url = _supportUrl('support_mine');
    final response = await client
        .get(
          url,
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer $token',
          },
        )
        .timeout(timeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const FormatException('پاسخ پشتیبانی معتبر نیست.');
    }
    if (response.statusCode != 200 ||
        decoded is! Map<String, dynamic> ||
        decoded['ok'] != true ||
        decoded['messages'] is! List) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message']
          : null;
      throw Exception(
        message is String ? message : 'دریافت پیام‌های پشتیبانی انجام نشد.',
      );
    }
    return (decoded['messages'] as List)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> logoutSupport(String token) async {
    await _supportPost('support_logout', const {}, token: token);
  }

  Future<List<LibraryArticle>> articles(String categoryId) async {
    final rows = (await _get({
      'cat_id': categoryId,
      'include_dates': '1',
      'include_views': '1',
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
      'include_dates': '1',
      'include_views': '1',
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
        : Uri(
            scheme: endpoint.scheme,
            host: endpoint.host,
            port: endpoint.hasPort ? endpoint.port : null,
            path: path.startsWith('/')
                ? path
                : path.startsWith('upload/')
                ? '/$path'
                : '/upload/category/$path',
          );
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }

  void close() => client.close();
}
