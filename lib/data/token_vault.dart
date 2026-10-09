import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'web_token_store_stub.dart'
    if (dart.library.js_interop) 'web_token_store_web.dart'
    as browser;

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenVault implements TokenVault {
  SecureTokenVault([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'divan.app.account.token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

class MemoryTokenVault implements TokenVault {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async => _token = token;
  @override
  Future<void> delete() async => _token = null;
}

class BrowserTokenVault implements TokenVault {
  final _store = browser.WebTokenStore();

  @override
  Future<String?> read() => _store.read();

  @override
  Future<void> write(String token) => _store.write(token);

  @override
  Future<void> delete() => _store.delete();
}
