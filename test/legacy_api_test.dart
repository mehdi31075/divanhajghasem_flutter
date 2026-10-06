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
    expect(paths.map((p) => p.query), ['', 'cat_id=61', 'nid=117']);
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
}
