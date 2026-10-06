import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/post_api.dart';
import 'package:hajqasem_app/domain/library.dart';
import 'package:hajqasem_app/domain/note.dart';

class FakePhp {
  final endpoint = Uri.parse('http://example.test/api.php');
  final articles = <LibraryArticle>[];
  bool authorized = true;
  bool offline = false;
  bool failReadAfterPost = false;
  bool timeoutAfterPost = false;
  bool ignorePost = false;
  bool malformedRead = false;
  int posts = 0;
  Future<void> Function()? afterPost;
  Map<String, String>? lastFields;
  http.Response json(List<Object> values) => http.Response(
    jsonEncode({'AndroidEbookApp': values}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw const SocketException('offline');
    if (request.url.path == '/api.php') {
      if (malformedRead) return http.Response('<html>error</html>', 200);
      final query = request.url.queryParameters;
      if (query.isEmpty) {
        return json([
          {'cid': '61', 'category_name': 'دسته اول'},
          {'cid': '62', 'category_name': 'دسته دوم'},
        ]);
      }
      return json(
        articles
            .where(
              (a) => query.containsKey('nid')
                  ? a.id == query['nid']
                  : a.categoryId == query['cat_id'],
            )
            .map((a) => a.toJson())
            .toList(),
      );
    }
    final path = request.url.path;
    if (request.method == 'GET') {
      // Even a redirect containing the protected form must not authorize POST.
      return http.Response(
        '<form><button name="btnAdd"></button><button name="btnEdit"></button><button name="btnDelete"></button></form>',
        authorized ? 200 : 302,
        headers: authorized ? {} : {'location': 'index.php'},
      );
    }
    posts++;
    lastFields = request.bodyFields;
    if (!ignorePost) {
      final id = request.url.queryParameters['id'] ?? '${100 + posts}';
      articles.removeWhere((a) => a.id == id);
      if (path != '/delete-menu.php') {
        articles.add(
          LibraryArticle(
            id: id,
            categoryId: lastFields!['cid']!,
            title: lastFields!['news_heading']!,
            subtitle: lastFields!['news_date']!,
            htmlBody: lastFields!['news_description']!,
          ),
        );
      }
    }
    await afterPost?.call();
    if (failReadAfterPost) offline = true;
    if (timeoutAfterPost) throw TimeoutException('Response lost');
    // Deliberately misleading PHP banner: success must come from the API.
    return http.Response('Update Failed', 500);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory folder;
  late NotebookDatabase database;
  late NotebookController controller;
  late FakePhp server;
  NotebookController connect() => NotebookController(
    database,
    api: LegacyApi(
      endpoint: server.endpoint,
      client: MockClient(server.handle),
    ),
    postApi: PostApi(
      server.endpoint,
      useTokens: false,
      client: MockClient(server.handle),
    ),
  );
  Future<Note> draft() => controller.save(
    Note.empty().copyWith(
      title: 'عنوان',
      subtitle: 'زیرعنوان',
      body: 'متن\nتازه',
      categoryId: controller.library.noteCategoryId('61'),
    ),
  );
  const existing = LibraryArticle(
    id: '7',
    categoryId: '61',
    title: 'قدیمی',
    subtitle: 'زیرعنوان',
    htmlBody: '<p><b>متن</b><img src="x.jpg"></p>',
  );

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('divan-posts-');
    database = await NotebookDatabase.open(
      path: '${folder.path}/db',
      factory: databaseFactoryFfi,
    );
    server = FakePhp();
    controller = connect();
    await controller.refreshCategories();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
    await folder.delete(recursive: true);
  });

  test(
    'create verifies server, atomically clears draft and keeps offline cache after restart',
    () async {
      final note = await draft();
      expect(await controller.publish(note), isNull);
      expect(server.posts, 1);
      expect(server.lastFields!['btnAdd'], '1');
      expect(server.lastFields!['news_description'], note.htmlBody);
      expect(await database.note(note.id), isNull);
      expect(await database.pendingCount(), 0);
      expect(await database.db.query('post_operations'), isEmpty);
      controller.dispose();
      await database.close();
      database = await NotebookDatabase.open(
        path: '${folder.path}/db',
        factory: databaseFactoryFfi,
      );
      server.offline = true;
      controller = connect();
      expect(
        (await controller.library.cachedArticles('61'))!.single.title,
        note.title,
      );
    },
  );

  test(
    'edit preserves HTML and removes old category cache when moved',
    () async {
      server.articles.add(existing);
      await controller.library.refreshArticles('61');
      await controller.library.refreshArticles('62');
      final edit = await controller.save(
        (await controller.draftForArticle(existing)).copyWith(
          title: 'ویرایش',
          categoryId: controller.library.noteCategoryId('62'),
        ),
      );
      await controller.publish(edit);
      expect(server.lastFields!['btnEdit'], '1');
      expect(server.articles.single.htmlBody, existing.htmlBody);
      expect(await controller.library.cachedArticles('61'), isEmpty);
      expect(
        (await controller.library.cachedArticles('62'))!.single.id,
        existing.id,
      );
    },
  );

  test('delete verifies absence and clears cached item', () async {
    server.articles.add(existing);
    await controller.library.refreshArticles('61');
    await controller.deletePost(existing);
    expect(server.lastFields!['btnDelete'], '1');
    expect(server.articles, isEmpty);
    expect(await controller.library.cachedArticles('61'), isEmpty);
  });

  test(
    'expired session preflight forbids mutation even with form in redirect body',
    () async {
      final note = await draft();
      server.authorized = false;
      await expectLater(
        controller.publish(note),
        throwsA(isA<LoginRequired>()),
      );
      expect(server.posts, 0);
      expect(await database.db.query('post_operations'), isEmpty);
      expect((await database.note(note.id))!.body, note.body);
    },
  );

  test(
    'offline before POST retains draft and does not create uncertain operation',
    () async {
      final note = await draft();
      server.offline = true;
      await expectLater(
        controller.publish(note),
        throwsA(isA<SocketException>()),
      );
      expect(server.posts, 0);
      expect(await database.note(note.id), isNotNull);
      expect(await database.db.query('post_operations'), isEmpty);
    },
  );

  test('timeout after committed POST is verified through GET', () async {
    final note = await draft();
    server.timeoutAfterPost = true;
    await controller.publish(note);
    expect(server.posts, 1);
    expect(await database.note(note.id), isNull);
  });

  test(
    'uncertain create survives restart and retry never repeats POST',
    () async {
      final note = await draft();
      server.failReadAfterPost = true;
      await expectLater(
        controller.publish(note),
        throwsA(isA<PostUnconfirmed>()),
      );
      expect(await controller.posts.pendingDraft(note.id), isTrue);
      controller.dispose();
      await database.close();
      database = await NotebookDatabase.open(
        path: '${folder.path}/db',
        factory: databaseFactoryFfi,
      );
      server.offline = false;
      controller = connect();
      await controller.publish((await database.note(note.id))!);
      expect(server.posts, 1);
      expect(await database.note(note.id), isNull);
    },
  );

  test(
    'late acknowledgement preserves newer draft and next save edits created article',
    () async {
      final note = await draft();
      server.afterPost = () async {
        await controller.save(note.copyWith(body: 'تغییر تازه‌تر'));
      };
      final remaining = await controller.publish(note);
      expect(remaining!.body, 'تغییر تازه‌تر');
      expect(remaining.original!.id, server.articles.single.id);
      expect(await database.pendingCount(), 1);
      server.afterPost = null;
      await controller.publish(remaining);
      expect(server.posts, 2);
      expect(server.lastFields!['btnEdit'], '1');
      expect(server.articles, hasLength(1));
      expect(await database.note(note.id), isNull);
    },
  );

  test(
    'cache transaction failure retains draft and journal for read-only retry',
    () async {
      final note = await draft();
      await database.db.execute(
        "CREATE TRIGGER fail_cache BEFORE INSERT ON library_cache BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      await expectLater(
        controller.publish(note),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.note(note.id), isNotNull);
      expect(await controller.posts.pendingDraft(note.id), isTrue);
      await database.db.execute('DROP TRIGGER fail_cache');
      await controller.publish(note);
      expect(server.posts, 1);
    },
  );

  test('server conflict prevents edit and delete, retaining draft', () async {
    final edit = await controller.save(
      await controller.draftForArticle(existing),
    );
    server.articles.add(
      const LibraryArticle(
        id: '7',
        categoryId: '61',
        title: 'someone else',
        subtitle: 'x',
        htmlBody: '<p>changed</p>',
      ),
    );
    await expectLater(controller.publish(edit), throwsA(isA<PostFailure>()));
    await expectLater(
      controller.deletePost(existing),
      throwsA(isA<PostFailure>()),
    );
    expect(server.posts, 0);
    expect(await database.note(edit.id), isNotNull);
  });

  test('uncommitted POST never reports success or retries blindly', () async {
    final note = await draft();
    server.ignorePost = true;
    await expectLater(
      controller.publish(note),
      throwsA(isA<PostUnconfirmed>()),
    );
    await expectLater(
      controller.publish(note),
      throwsA(isA<PostUnconfirmed>()),
    );
    expect(server.posts, 1);
    expect(await database.note(note.id), isNotNull);
  });

  test(
    'malformed read after delete keeps cache and pending verification',
    () async {
      server.articles.add(existing);
      await controller.library.refreshArticles('61');
      server.afterPost = () async {
        server.malformedRead = true;
      };
      await expectLater(
        controller.deletePost(existing),
        throwsA(isA<PostUnconfirmed>()),
      );
      expect((await controller.library.cachedArticles('61'))!.single.id, '7');
      server.malformedRead = false;
      await controller.deletePost(existing);
      expect(server.posts, 1);
    },
  );

  test('reopening article resumes its existing unsent draft', () async {
    final edit = await controller.save(
      (await controller.draftForArticle(existing)).copyWith(title: 'پیش‌نویس'),
    );
    final reopened = await controller.draftForArticle(existing);
    expect(reopened.id, edit.id);
    expect(reopened.title, edit.title);
  });

  test('draft belonging to another source is never sent', () async {
    final note = (await draft()).copyWith(
      serverSource: 'http://other.test/api.php',
    );
    await expectLater(controller.publish(note), throwsA(isA<PostFailure>()));
    expect(server.posts, 0);
  });
}
