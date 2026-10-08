import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/data/post_api.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'post_service_test.dart' show FakePhp;
import 'token_api_test.dart' show token, reply;

class FakeTokenPhp extends FakePhp {
  bool rejectWrite = false;
  int panelRequests = 0;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/api.php') return super.handle(request);
    if (request.url.path != '/mobile-api.php') {
      panelRequests++;
      throw StateError('Token mode must not call a panel form');
    }
    final action = request.url.queryParameters['action'];
    if (action == 'login') {
      return reply({'ok': true, 'access_token': token, 'token_type': 'Bearer'});
    }
    expect(request.headers['authorization'], 'Bearer $token');
    if (!authorized) return reply({'ok': false, 'error': 'unauthorized'}, 401);
    if (action == 'me' || action == 'logout') return reply({'ok': true});
    if (rejectWrite) {
      return reply({'ok': false, 'message': 'متن معتبر نیست.'}, 422);
    }
    final path = switch (action) {
      'create' => 'add-menu.php',
      'update' => 'edit-menu.php',
      'delete' => 'delete-menu.php',
      _ => throw StateError('Unexpected action'),
    };
    final id = request.bodyFields['id'];
    final forwarded = http.Request(
      'POST',
      endpoint
          .resolve(path)
          .replace(queryParameters: id == null ? null : {'id': id}),
    )..bodyFields = request.bodyFields;
    await super.handle(forwarded);
    return reply({'ok': true});
  }
}

void main() {
  sqfliteFfiInit();
  late NotebookDatabase db;
  late NotebookController controller;
  late FakeTokenPhp server;
  setUp(() async {
    db = await NotebookDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    server = FakeTokenPhp();
    controller = NotebookController(
      db,
      api: LegacyApi(
        endpoint: server.endpoint,
        client: MockClient(server.handle),
      ),
      postApi: PostApi(server.endpoint, client: MockClient(server.handle)),
    );
    await controller.refreshCategories();
    await controller.posts.api.login('fixture-admin', 'fixture-password');
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  Future<Note> draft() => controller.save(
    Note.empty().copyWith(
      title: 'عنوان',
      subtitle: 'زیرعنوان',
      body: 'متن فارسی',
      categoryId: controller.library.noteCategoryId('61'),
    ),
  );

  test(
    'token create/edit/delete verify the public API and keep no published local note',
    () async {
      final note = await draft();
      expect(await controller.publish(note), isNull);
      expect(await db.note(note.id), isNull);
      final article = server.articles.single;
      final edit = await controller.save(
        Note.empty().copyWith(
          title: 'عنوان ویرایش‌شده',
          subtitle: article.subtitle,
          body: article.htmlBody,
          bodyIsHtml: true,
          serverBase: jsonEncode(article.toJson()),
          serverSource: server.endpoint.toString(),
          categoryId: controller.library.noteCategoryId('61'),
        ),
      );
      expect(await controller.publish(edit), isNull);
      expect(server.articles.single.title, 'عنوان ویرایش‌شده');
      await controller.posts.delete(server.articles.single);
      expect(server.articles, isEmpty);
      expect(server.posts, 3);
      expect(server.panelRequests, 0);
    },
  );

  test('expired token never posts and retains the draft', () async {
    final note = await draft();
    server.authorized = false;
    await expectLater(controller.publish(note), throwsA(isA<LoginRequired>()));
    expect(server.posts, 0);
    expect(await db.note(note.id), isNotNull);
    expect(await controller.posts.pendingDraft(note.id), isFalse);
  });

  test(
    'definite rejection releases operation journal for correction without losing the draft',
    () async {
      final note = await draft();
      server.rejectWrite = true;
      await expectLater(controller.publish(note), throwsA(isA<PostRejected>()));
      expect(await controller.posts.pendingDraft(note.id), isFalse);
      expect(await db.note(note.id), isNotNull);
      expect(server.posts, 0);
      server.rejectWrite = false;
      expect(await controller.publish(note), isNull);
      expect(server.posts, 1);
    },
  );

  test(
    'connection loss after token POST is reconciled read-only with no duplicate',
    () async {
      final note = await draft();
      server.failReadAfterPost = true;
      server.timeoutAfterPost = true;
      await expectLater(
        controller.publish(note),
        throwsA(isA<PostUnconfirmed>()),
      );
      expect(await controller.posts.pendingDraft(note.id), isTrue);
      expect(await db.note(note.id), isNotNull);
      server.offline = false;
      expect(await controller.publish(note), isNull);
      expect(server.posts, 1);
      expect(server.articles.length, 1);
    },
  );
}
