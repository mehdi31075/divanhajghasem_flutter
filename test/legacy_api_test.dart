import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/domain/library.dart';

Map<String, Object> articleJson({String body = '<p>سلام<br>دنیا</p>'}) => {
  'nid': '117',
  'cat_id': '61',
  'news_heading': 'عنوان فارسی',
  'news_date': 'عنوان فرعی',
  'news_description': body,
};

Map<String, Object> categoryJson() => {
  'cid': '61',
  'category_name': 'دستهٔ فارسی',
  'category_image': 'cover.png',
  'author': 'نویسنده',
};

http.Response apiResponse(List<Map<String, Object>> rows) =>
    http.Response.bytes(
      utf8.encode(jsonEncode({'AndroidEbookApp': rows})),
      200,
    );

void main() {
  test('existing API routes, UTF-8, subtitle and HTML are preserved', () async {
    final paths = <Uri>[];
    final api = LegacyApi(
      client: MockClient((request) async {
        paths.add(request.url);
        return apiResponse(
          request.url.queryParameters.isEmpty
              ? [categoryJson()]
              : [articleJson()],
        );
      }),
    );
    addTearDown(api.close);
    expect(api.endpoint.path, '/index.php/api.php');
    expect(api.endpoint.resolve('pages.php').path, '/index.php/pages.php');
    final categories = await api.categories();
    final articles = await api.articles('61');
    final detail = await api.article('117');
    expect(categories.single.name, 'دستهٔ فارسی');
    expect(
      api.categoryImage(categories.single).toString(),
      'http://divanhajghasem.ir/upload/category/cover.png',
    );
    expect(
      api
          .categoryImage(
            const LibraryCategory(
              id: '61',
              name: 'دستهٔ فارسی',
              image: 'upload/category/cover.png',
            ),
          )
          .toString(),
      'http://divanhajghasem.ir/upload/category/cover.png',
    );
    expect(paths.map((p) => p.query), [
      '',
      'cat_id=61&include_dates=1&include_views=1',
      'nid=117&include_dates=1&include_views=1',
    ]);
    expect(articles.single.subtitle, 'عنوان فرعی');
    expect(detail.htmlBody, '<p>سلام<br>دنیا</p>');
  });

  test('numeric IDs and the empty PHP array are supported', () async {
    var count = 0;
    final api = LegacyApi(
      client: MockClient(
        (_) async => count++ == 0
            ? apiResponse([
                {...categoryJson(), 'cid': 61},
              ])
            : http.Response('[]', 200),
      ),
    );
    addTearDown(api.close);
    expect((await api.categories()).single.id, '61');
    expect(await api.articles('61'), isEmpty);
  });

  test('malformed, error, and wrong-category responses are rejected', () async {
    for (final response in [
      http.Response('<html>error</html>', 200),
      http.Response('{}', 200),
      http.Response('[]', 503),
      apiResponse([
        {'nid': '117'},
      ]),
      apiResponse([
        {...articleJson(), 'cat_id': '62'},
      ]),
    ]) {
      final api = LegacyApi(client: MockClient((_) async => response));
      await expectLater(api.articles('61'), throwsA(isA<Exception>()));
      api.close();
    }
  });

  test('network requests have a bounded timeout', () async {
    final pending = Completer<http.Response>();
    final api = LegacyApi(
      client: MockClient((_) => pending.future),
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(api.close);
    await expectLater(api.categories(), throwsA(isA<TimeoutException>()));
    pending.complete(http.Response('[]', 200));
  });

  test(
    'support requires a phone OTP session and lists replies by account',
    () async {
      final requests = <http.Request>[];
      final token = List.filled(64, 'a').join();
      final api = LegacyApi(
        endpoint: Uri.parse('http://divanhajghasem.ir/index.php/api.php'),
        client: MockClient((request) async {
          requests.add(request);
          final action = request.url.queryParameters['action'];
          final response = switch (action) {
            'support_start' => {
              'ok': true,
              'challenge_id': List.filled(64, 'b').join(),
              'test_otp': '012345',
              'mode': 'register',
            },
            'support_verify' => {
              'ok': true,
              'access_token': token,
              'user': {'name': 'کاربر آزمایشی', 'mobile': '+989123456789'},
            },
            'support_send' => {'ok': true},
            'support_mine' => {
              'ok': true,
              'messages': [
                {
                  'message': 'انتقاد فارسی',
                  'reply': 'پاسخ مدیر',
                  'created_at': '2026-10-09T12:00:00Z',
                  'replied_at': '2026-10-09T13:00:00Z',
                },
              ],
            },
            'support_logout' => {'ok': true},
            _ => {'ok': false, 'message': 'unknown action'},
          };
          return http.Response.bytes(
            utf8.encode(jsonEncode(response)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);
      final challenge = await api.startSupportOtp(
        'کاربر آزمایشی',
        '۰۹۱۲۳۴۵۶۷۸۹',
      );
      expect(challenge['test_otp'], '012345');
      expect(challenge['mode'], 'register');
      final session = await api.verifySupportOtp(
        challenge['challenge_id'] as String,
        challenge['test_otp'] as String,
      );
      expect(session['access_token'], token);
      await api.submitSupportMessage(token, 'انتقاد فارسی');
      expect((await api.supportMessages(token)).single['reply'], 'پاسخ مدیر');
      await api.logoutSupport(token);
      expect(requests.map((request) => request.url.scheme).toSet(), {'https'});
      expect(requests.map((request) => request.url.path).toSet(), {
        '/index.php/mobile-api.php',
      });
      expect(requests.map((request) => request.url.queryParameters['action']), [
        'support_start',
        'support_verify',
        'support_send',
        'support_mine',
        'support_logout',
      ]);
      expect(requests.first.bodyFields, {
        'name': 'کاربر آزمایشی',
        'mobile': '۰۹۱۲۳۴۵۶۷۸۹',
      });
      expect(requests[2].headers['authorization'], 'Bearer $token');
      expect(requests[3].headers['authorization'], 'Bearer $token');
      expect(requests[2].bodyFields, {'message': 'انتقاد فارسی'});
      expect(requests[0].bodyFields.containsKey('receipt'), isFalse);
    },
  );

  test(
    'app account onboarding asks for name only after OTP and records public views',
    () async {
      final requests = <http.Request>[];
      final token = List.filled(64, 'c').join();
      var verification = 0;
      final api = LegacyApi(
        client: MockClient((request) async {
          requests.add(request);
          final action = request.url.queryParameters['action'];
          final result = switch (action) {
            'user_start' => {
              'ok': true,
              'challenge_id': List.filled(64, 'd').join(),
              'test_otp': '123456',
              'mode': 'register',
            },
            'user_verify' when verification++ == 0 => {
              'ok': true,
              'needs_name': true,
              'mode': 'register',
            },
            'user_verify' => {
              'ok': true,
              'access_token': token,
              'user': {'id': '7', 'name': 'نام', 'mobile': '+989123456789'},
            },
            'user_me' => {
              'ok': true,
              'user': {'id': '7', 'name': 'نام', 'mobile': '+989123456789'},
            },
            'user_logout' => {'ok': true},
            'article_view' => {'ok': true, 'nid': '117', 'views': 9},
            _ => {'ok': false},
          };
          return http.Response.bytes(utf8.encode(jsonEncode(result)), 200);
        }),
      );
      addTearDown(api.close);

      final start = await api.startAccountOtp('09123456789');
      final challenge = start['challenge_id'] as String;
      final needsName = await api.verifyAccountOtp(challenge, '123456');
      expect(needsName['needs_name'], true);
      final login = await api.verifyAccountOtp(
        challenge,
        '123456',
        name: 'نام',
      );
      expect(login['access_token'], token);
      expect((await api.accountUser(token))['name'], 'نام');
      expect(await api.incrementArticleView('117'), 9);
      await api.logoutAccount(token);
      expect(requests.map((request) => request.url.queryParameters['action']), [
        'user_start',
        'user_verify',
        'user_verify',
        'user_me',
        'article_view',
        'user_logout',
      ]);
      expect(requests.first.bodyFields, {'mobile': '09123456789'});
      expect(requests[2].bodyFields['name'], 'نام');
      expect(requests[4].bodyFields, {'nid': '117'});
    },
  );
}
