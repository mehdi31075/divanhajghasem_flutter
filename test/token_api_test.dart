import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hajqasem_app/data/post_api.dart';

const token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
http.Response reply(Map<String, dynamic> body, [int code = 200]) =>
    http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test(
    'token login, preflight, create, edit, delete and revocation use Bearer without panel requests',
    () async {
      final requests = <http.Request>[];
      final api = PostApi(
        Uri.parse('http://example.test/api.php'),
        client: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/mobile-api.php');
          expect(request.headers.containsKey('cookie'), isFalse);
          final action = request.url.queryParameters['action'];
          if (action == 'login') {
            expect(request.headers.containsKey('authorization'), isFalse);
            expect(request.bodyFields, {
              'username': 'fixture-admin',
              'password': 'fixture-password',
            });
            return reply({
              'ok': true,
              'access_token': token,
              'token_type': 'Bearer',
              'expires_in': 3600,
            });
          }
          expect(request.headers['authorization'], 'Bearer $token');
          if (action == 'me') expect(request.method, 'GET');
          return reply({'ok': true});
        }),
      );
      addTearDown(api.close);
      await api.login('fixture-admin', 'fixture-password');
      expect(api.authenticated, isTrue);
      await api.requireForm('add-menu.php', 'btnAdd');
      await api.submit('add-menu.php', {'news_heading': 'عنوان', 'cid': '61'});
      await api.submit('edit-menu.php', {'news_heading': 'ویرایش'}, '7');
      await api.submit('delete-menu.php', {}, '7');
      expect(requests[3].url.queryParameters['action'], 'create');
      expect(requests[4].url.queryParameters['action'], 'update');
      expect(requests[4].bodyFields['id'], '7');
      expect(requests[5].url.queryParameters['action'], 'delete');
      await api.logout();
      expect(requests.last.url.queryParameters['action'], 'logout');
      expect(api.authenticated, isFalse);
      await expectLater(
        api.requireForm('add-menu.php', 'btnAdd'),
        throwsA(isA<LoginRequired>()),
      );
      expect(requests.length, 7);
    },
  );

  test('wrong credentials never unlock management', () async {
    final api = PostApi(
      Uri.parse('http://example.test/api.php'),
      client: MockClient(
        (_) async => reply({'ok': false, 'error': 'invalid_credentials'}, 401),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.login('wrong', 'wrong'),
      throwsA(isA<InvalidCredentials>()),
    );
    expect(api.canManage, isFalse);
  });

  test(
    'malformed token response and failed verification do not unlock',
    () async {
      for (final scenario in ['malformed', 'expired']) {
        final api = PostApi(
          Uri.parse('http://example.test/api.php'),
          client: MockClient((request) async {
            if (request.url.queryParameters['action'] == 'login') {
              return reply({
                'ok': true,
                'access_token': scenario == 'malformed' ? 'invalid' : token,
                'token_type': 'Bearer',
              });
            }
            return reply({'ok': false}, 401);
          }),
        );
        await expectLater(
          api.login('fixture-admin', 'fixture-password'),
          throwsA(isA<PostFailure>()),
        );
        expect(api.canManage, isFalse);
        api.close();
      }
    },
  );

  test('expired token locks management before a mutation is sent', () async {
    var expired = false;
    var mutations = 0;
    final api = PostApi(
      Uri.parse('http://example.test/api.php'),
      client: MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (action == 'login') {
          return reply({
            'ok': true,
            'access_token': token,
            'token_type': 'Bearer',
          });
        }
        if (action == 'me') return reply({'ok': !expired}, expired ? 401 : 200);
        mutations++;
        return reply({'ok': true});
      }),
    );
    addTearDown(api.close);
    await api.login('fixture-admin', 'fixture-password');
    expired = true;
    await expectLater(
      api.requireForm('edit-menu.php', 'btnEdit', '7'),
      throwsA(isA<LoginRequired>()),
    );
    expect(api.authenticated, isFalse);
    expect(mutations, 0);
  });

  test(
    'missing token endpoint tells the user deployment is required',
    () async {
      final api = PostApi(
        Uri.parse('http://example.test/api.php'),
        client: MockClient((_) async => http.Response('<html>404</html>', 404)),
      );
      addTearDown(api.close);
      await expectLater(
        api.login('fixture-admin', 'fixture-password'),
        throwsA(
          isA<PostFailure>().having(
            (e) => e.message,
            'message',
            contains('نصب نشده'),
          ),
        ),
      );
      expect(api.canManage, isFalse);
    },
  );

  test(
    'a definite validation error is different from an uncertain server failure',
    () async {
      var status = 422;
      final api = PostApi(
        Uri.parse('http://example.test/api.php'),
        client: MockClient((request) async {
          final action = request.url.queryParameters['action'];
          if (action == 'login') {
            return reply({
              'ok': true,
              'access_token': token,
              'token_type': 'Bearer',
            });
          }
          if (action == 'me') return reply({'ok': true});
          return reply({
            'ok': false,
            'error': 'missing_field',
            'message': 'متن معتبر نیست.',
          }, status);
        }),
      );
      addTearDown(api.close);
      await api.login('fixture-admin', 'fixture-password');
      await expectLater(
        api.submit('add-menu.php', {}),
        throwsA(isA<PostRejected>()),
      );
      status = 500;
      await expectLater(
        api.submit('add-menu.php', {}),
        throwsA(
          isA<PostFailure>().having(
            (e) => e is PostRejected,
            'rejected',
            isFalse,
          ),
        ),
      );
    },
  );

  test(
    'JSON article-not-found is a rejection, not a missing endpoint',
    () async {
      final api = PostApi(
        Uri.parse('http://example.test/api.php'),
        client: MockClient((request) async {
          final action = request.url.queryParameters['action'];
          if (action == 'login') {
            return reply({
              'ok': true,
              'access_token': token,
              'token_type': 'Bearer',
            });
          }
          if (action == 'me') return reply({'ok': true});
          return reply({
            'ok': false,
            'error': 'article_not_found',
            'message': 'مطلب وجود ندارد.',
          }, 404);
        }),
      );
      addTearDown(api.close);
      await api.login('fixture-admin', 'fixture-password');
      await expectLater(
        api.submit('edit-menu.php', {}, '7'),
        throwsA(
          isA<PostRejected>().having(
            (e) => e.message,
            'message',
            'مطلب وجود ندارد.',
          ),
        ),
      );
    },
  );
}
