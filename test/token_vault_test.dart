import 'package:flutter_test/flutter_test.dart';
import 'package:hajqasem_app/data/token_vault.dart';

void main() {
  test('browser token vault keeps a session across app instances', () async {
    final firstRun = BrowserTokenVault();
    final token = List.filled(64, 'a').join();

    await firstRun.write(token);
    expect(await BrowserTokenVault().read(), token);

    await BrowserTokenVault().delete();
    expect(await firstRun.read(), isNull);
  });
}
