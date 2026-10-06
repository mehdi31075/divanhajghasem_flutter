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

class PreviewOnlyAccess extends PostFailure {
  const PreviewOnlyAccess()
    : super(
        'ورود آزمایشی فقط ابزارهای مدیریت را باز می‌کند. برای ثبت تغییر روی سایت، ورود واقعی سرور لازم است.',
      );
}

class PostUnconfirmed extends PostFailure {
  const PostUnconfirmed()
    : super(
        'نتیجهٔ درخواست هنوز مشخص نیست. پیش‌نویس محفوظ است؛ «بررسی نتیجه» را بزنید. درخواست تکراری ارسال نمی‌شود.',
      );
}

/// Adapts the existing PHP endpoints; no web view or local backend is used.
class PostApi extends ChangeNotifier {
  PostApi(
    this.endpoint, {
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : client = client ?? sessionClient(endpoint);
  final Uri endpoint;
  final http.Client client;
  final Duration timeout;
  bool _authenticated = false;
  bool _localPreviewAdmin = false;
  bool get authenticated => _authenticated;
  bool get localPreviewAdmin => kDebugMode && _localPreviewAdmin;
  bool get canManage => authenticated || localPreviewAdmin;

  // Temporary preview access. This branch is compiled out of release builds.
  bool unlockLocalPreview(String username, String password) {
    if (!kDebugMode ||
        username.trim().toLowerCase() != 'admin' ||
        password != const String.fromEnvironment('DIVAN_PREVIEW_PASSWORD')) {
      return false;
    }
    if (!_localPreviewAdmin) {
      _localPreviewAdmin = true;
      notifyListeners();
    }
    return true;
  }

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

  Future<void> login(String username, String password) async {
    authenticated = false;
    final response = await _request(
      'POST',
      url('index.php'),
      redirects: true,
      fields: {'username': username, 'password': password, 'btnLogin': '1'},
    );
    if (response.statusCode >= 400) {
      throw PostFailure('سرور ورود را نپذیرفت (کد ${response.statusCode}).');
    }
    // The existing PHP form reports a credential mismatch in its HTML, not
    // with an HTTP error status. Do not report that as a cookie/network error.
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
    if (localPreviewAdmin && !authenticated) {
      throw const PreviewOnlyAccess();
    }
    late http.Response response;
    try {
      response = await _request('GET', url(path, id));
    } catch (_) {
      // Browsers report a blocked redirect as a ClientException. A subsequent
      // attempt must be able to sign in again after session expiration.
      authenticated = false;
      rethrow;
    }
    final document = html.parse(utf8.decode(response.bodyBytes));
    // The old PHP wrapper redirects without exiting. Never POST on a failed
    // preflight, even if its response happens to contain the protected form.
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
    await _request('POST', url(path, id), fields: fields);
    // PHP's HTML banners are unreliable. PostService verifies via the read API.
  }

  Future<void> logout() async {
    final hadServerSession = authenticated;
    _localPreviewAdmin = false;
    authenticated = false;
    notifyListeners();
    if (!hadServerSession) return;
    try {
      await _request('GET', url('logout.php'));
    } catch (_) {
      // The local editor stays locked even when the server is unavailable.
    }
  }

  void close() {
    client.close();
    dispose();
  }
}
