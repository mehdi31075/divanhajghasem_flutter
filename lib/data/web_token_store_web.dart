import 'package:web/web.dart' as web;

class WebTokenStore {
  static const _key = 'divan.app.account.token';

  Future<String?> read() async => web.window.localStorage.getItem(_key);

  Future<void> write(String token) async =>
      web.window.localStorage.setItem(_key, token);

  Future<void> delete() async => web.window.localStorage.removeItem(_key);
}
