import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'session_client.dart';

class PostFailure implements Exception {
  const PostFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class LoginRequired extends PostFailure {
  const LoginRequired() : super('برای ذخیره روی سرور، وارد حساب شوید.');
}

class InvalidCredentials extends PostFailure {
  const InvalidCredentials() : super('نام کاربری یا رمز عبور پذیرفته نشد.');
}

class LoginSessionUnavailable extends PostFailure {
  const LoginSessionUnavailable()
    : super('سرور نشست ورود را برای درخواست بعدی نگه نداشت.');
}

/// A definite rejection from the token API, before any change was committed.
class PostRejected extends PostFailure {
  const PostRejected(super.message);
}

class PostUnconfirmed extends PostFailure {
  const PostUnconfirmed()
    : super(
        'نتیجهٔ درخواست هنوز مشخص نیست. پیش‌نویس محفوظ است؛ «بررسی نتیجه» را بزنید. درخواست تکراری ارسال نمی‌شود.',
      );
}

/// Token API by default; the existing PHP session adapter remains opt-in.
class PostApi extends ChangeNotifier {
  PostApi(
    this.endpoint, {
    http.Client? client,
    Uri? tokenEndpoint,
    this.useTokens = const bool.fromEnvironment(
      'DIVAN_USE_TOKENS',
      defaultValue: true,
    ),
    this.timeout = const Duration(seconds: 45),
  }) : tokenEndpoint =
           tokenEndpoint ??
           (const String.fromEnvironment('DIVAN_TOKEN_API_URL').isEmpty
               ? endpoint.resolve('mobile-api.php').replace(scheme: 'https')
               : Uri.parse(
                   const String.fromEnvironment('DIVAN_TOKEN_API_URL'),
                 )),
       client = client ?? (useTokens ? http.Client() : sessionClient(endpoint));
  final Uri endpoint;
  final Uri tokenEndpoint;
  final http.Client client;
  final bool useTokens;
  final Duration timeout;
  bool _authenticated = false;
  String? _token;
  bool get authenticated => _authenticated;
  bool get canManage => authenticated;

  set authenticated(bool value) {
    if (_authenticated == value) return;
    _authenticated = value;
    notifyListeners();
  }

  Uri url(String path, [String? id]) => endpoint
      .resolve(path)
      .replace(queryParameters: id == null ? null : {'id': id});

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? fields,
    bool redirects = false,
  }) async {
    final request = http.Request(method, uri)..followRedirects = redirects;
    request.headers['cache-control'] = 'no-cache';
    if (fields != null) request.bodyFields = fields;
    return await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(timeout);
  }

  Future<Map<String, dynamic>> _json(
    String action, {
    String method = 'POST',
    Map<String, String>? fields,
  }) async {
    final request = http.Request(
      method,
      tokenEndpoint.replace(queryParameters: {'action': action}),
    )..followRedirects = false;
    request.headers['accept'] = 'application/json';
    if (_token != null) request.headers['authorization'] = 'Bearer $_token';
    if (fields != null) request.bodyFields = fields;
    final response = await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(timeout);
    if (response.statusCode == 401) {
      _token = null;
      authenticated = false;
      if (action == 'login') throw const InvalidCredentials();
      if (action == 'me') throw const LoginRequired();
      throw const PostRejected('ورود منقضی شده است؛ دوباره وارد حساب شوید.');
    }
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      /* Treat non-JSON responses as uncertain, not success. */
    }
    if (response.statusCode == 404 && data == null) {
      throw const PostFailure(
        'API ورود با توکن هنوز روی سرور نصب نشده است. فایل‌های بک‌اند و migration باید روی سایت اعمال شوند.',
      );
    }
    if (response.statusCode >= 400 &&
        response.statusCode < 500 &&
        data != null) {
      throw PostRejected(data['message'] as String? ?? 'درخواست پذیرفته نشد.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data == null ||
        data['ok'] != true) {
      throw const PostFailure('پاسخ معتبر از API مدیریت دریافت نشد.');
    }
    return data;
  }

  Future<void> login(String username, String password) async {
    _token = null;
    authenticated = false;
    if (useTokens) {
      final data = await _json(
        'login',
        fields: {'username': username, 'password': password},
      );
      final token = data['access_token'];
      if (token is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
          data['token_type'] != 'Bearer') {
        throw const PostFailure('پاسخ ورود معتبر نیست.');
      }
      _token = token;
      try {
        await _json('me', method: 'GET');
      } catch (_) {
        _token = null;
        rethrow;
      }
      authenticated = true;
      return;
    }
    final response = await _request(
      'POST',
      url('index.php'),
      redirects: true,
      fields: {'username': username, 'password': password, 'btnLogin': '1'},
    );
    if (response.statusCode >= 400) {
      throw PostFailure('سرور ورود را نپذیرفت (کد ${response.statusCode}).');
    }
    if (html
            .parse(utf8.decode(response.bodyBytes))
            .body
            ?.text
            .contains('خطا در ورود') ??
        false) {
      throw const InvalidCredentials();
    }
    try {
      await requireForm('add-menu.php', 'btnAdd');
    } on LoginRequired {
      throw const LoginSessionUnavailable();
    }
    authenticated = true;
  }

  Future<void> requireForm(String path, String button, [String? id]) async {
    if (useTokens) {
      if (_token == null) {
        authenticated = false;
        throw const LoginRequired();
      }
      await _json('me', method: 'GET');
      return;
    }
    late http.Response response;
    try {
      response = await _request('GET', url(path, id));
    } catch (_) {
      authenticated = false;
      rethrow;
    }
    final document = html.parse(utf8.decode(response.bodyBytes));
    // Legacy wrappers redirect without exiting; a form alone is not authority.
    if (response.statusCode != 200 ||
        document.querySelector('input[type="password"]') != null ||
        document.querySelector('[name="$button"]') == null) {
      authenticated = false;
      throw const LoginRequired();
    }
  }

  Future<void> submit(
    String path,
    Map<String, String> fields, [
    String? id,
  ]) async {
    if (useTokens) {
      if (_token == null) throw const PostRejected('ابتدا وارد حساب شوید.');
      final action = switch (path) {
        'add-menu.php' => 'create',
        'edit-menu.php' => 'update',
        'delete-menu.php' => 'delete',
        _ => throw const PostRejected('عملیات پشتیبانی نمی‌شود.'),
      };
      await _json(action, fields: {...fields, 'id': ?id});
      return;
    }
    await _request('POST', url(path, id), fields: fields);
    // Both transports are confirmed by PostService via a subsequent read.
  }

  Future<void> logout() async {
    final hadServerSession = authenticated;
    try {
      if (_token != null && useTokens) {
        await _json('logout');
      } else if (hadServerSession && !useTokens) {
        await _request('GET', url('logout.php'));
      }
    } catch (_) {
      // Clear local access even if server revocation could not be reached.
    } finally {
      _token = null;
      authenticated = false;
    }
  }

  void close() {
    _token = null;
    client.close();
    dispose();
  }
}
