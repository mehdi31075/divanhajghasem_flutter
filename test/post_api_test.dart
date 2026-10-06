import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hajqasem_app/data/post_api.dart';

void main() {
  test(
    'login sends the existing PHP fields and verifies the authenticated form',
    () async {
      final requests = <http.Request>[];
      final api = PostApi(
        useTokens: false,
        Uri.parse('http://example.test/api.php'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            return http.Response(
              '',
              302,
              headers: {'location': 'dashboard.php'},
            );
          }
          return http.Response(
            '<form><button name="btnAdd">Add</button></form>',
            200,
          );
        }),
      );
      addTearDown(api.close);
      await api.login('test-user', 'dummy-password');
      expect(requests.first.url.path, '/index.php');
      expect(requests.first.bodyFields, {
        'username': 'test-user',
        'password': 'dummy-password',
        'btnLogin': '1',
      });
      expect(requests.last.method, 'GET');
      expect(requests.last.url.path, '/add-menu.php');
      expect(api.authenticated, isTrue);
    },
  );

  test(
    'browser redirect exception invalidates session so the next attempt can log in',
    () async {
      final api = PostApi(
        useTokens: false,
        Uri.parse('http://example.test/api.php'),
        client: MockClient((_) async {
          throw http.ClientException('Redirect disallowed');
        }),
      )..authenticated = true;
      addTearDown(api.close);
      await expectLater(
        api.requireForm('edit-menu.php', 'btnEdit', '7'),
        throwsA(isA<http.ClientException>()),
      );
      expect(api.authenticated, isFalse);
    },
  );

  test('PHP credential error is distinct from a lost session', () async {
    var requests = 0;
    final api = PostApi(
      useTokens: false,
      Uri.parse('http://example.test/api.php'),
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '<div>خطا در ورود</div>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.login('wrong-user', 'wrong-password'),
      throwsA(isA<InvalidCredentials>()),
    );
    expect(requests, 1);
    expect(api.authenticated, isFalse);
  });

  test(
    'successful form POST without a persistent session is rejected',
    () async {
      final api = PostApi(
        useTokens: false,
        Uri.parse('http://example.test/api.php'),
        client: MockClient(
          (request) async => request.method == 'POST'
              ? http.Response('', 302, headers: {'location': 'dashboard.php'})
              : http.Response('<input type="password">', 200),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.login('test-user', 'dummy-password'),
        throwsA(isA<LoginSessionUnavailable>()),
      );
      expect(api.authenticated, isFalse);
    },
  );
}
