import 'dart:io';
import 'package:http/http.dart' as http;

http.Client sessionClient(Uri origin) => _SessionClient(origin);

class _SessionClient extends http.BaseClient {
  _SessionClient(this.origin);
  final Uri origin;
  final _client = HttpClient();
  final Map<String, Cookie> _cookies = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != origin.origin) {
      throw http.ClientException('Unexpected server origin');
    }
    final outgoing = await _client.openUrl(request.method, request.url);
    outgoing.followRedirects = false;
    request.headers.forEach(outgoing.headers.set);
    outgoing.cookies.addAll(_cookies.values);
    await outgoing.addStream(request.finalize());
    final incoming = await outgoing.close();
    for (final cookie in incoming.cookies) {
      if (cookie.maxAge == 0) {
        _cookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie;
      }
    }
    final headers = <String, String>{};
    incoming.headers.forEach(
      (name, values) => headers[name] = values.join(','),
    );
    return http.StreamedResponse(
      incoming,
      incoming.statusCode,
      headers: headers,
      request: request,
    );
  }

  @override
  void close() {
    _cookies.clear();
    _client.close(force: true);
    super.close();
  }
}
