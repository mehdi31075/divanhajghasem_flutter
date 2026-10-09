class WebTokenStore {
  static String? _token;

  Future<String?> read() async => _token;

  Future<void> write(String token) async => _token = token;

  Future<void> delete() async => _token = null;
}
