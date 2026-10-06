import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/library_repository.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'legacy_api_test.dart' show apiResponse, articleJson, categoryJson;

void main() {
  sqfliteFfiInit();
  late Directory folder;
  late NotebookDatabase database;
  late String path;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('divan-library-');
    path = '${folder.path}/notebook.db';
    database = await NotebookDatabase.open(
      path: path,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await database.close();
    await folder.delete(recursive: true);
  });

  test(
    'downloaded HTML survives restart and failed refresh; local edits are untouched',
    () async {
      var online = true;
      final api = LegacyApi(
        client: MockClient((request) async {
          if (!online) throw const SocketException('offline');
          return apiResponse(
            request.url.queryParameters.isEmpty
                ? [categoryJson()]
                : [articleJson()],
          );
        }),
      );
      addTearDown(api.close);
      final note = await database.save(
        Note.empty().copyWith(body: 'یادداشت شخصی'),
      );
      var repository = LibraryRepository(database, api);
      await repository.refreshCategories();
      final snapshot = (await repository.refreshArticles('61')).single;
      await database.close();
      database = await NotebookDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      repository = LibraryRepository(database, api);
      online = false;
      expect((await repository.cachedCategories())!.single.id, '61');
      expect(
        (await repository.cachedArticles('61'))!.single.htmlBody,
        snapshot.htmlBody,
      );
      await expectLater(
        repository.refreshArticles('61'),
        throwsA(isA<SocketException>()),
      );
      expect(
        (await repository.cachedArticles('61'))!.single.htmlBody,
        snapshot.htmlBody,
      );
      expect((await database.note(note.id))!.body, 'یادداشت شخصی');
      expect(await database.pendingCount(), 1);
      expect(await database.versions(note.id), isEmpty);
    },
  );

  test(
    'malformed responses and failed cache commits preserve the old content',
    () async {
      var response = apiResponse([articleJson()]);
      final api = LegacyApi(client: MockClient((_) async => response));
      addTearDown(api.close);
      final repository = LibraryRepository(database, api);
      final original = (await repository.refreshArticles('61')).single;
      response = http.Response('{}', 200);
      await expectLater(
        repository.refreshArticles('61'),
        throwsFormatException,
      );
      expect(
        (await repository.cachedArticles('61'))!.single.htmlBody,
        original.htmlBody,
      );
      response = apiResponse([articleJson(body: '<p>تازه</p>')]);
      await database.db.execute(
        "CREATE TRIGGER fail_library BEFORE INSERT ON library_cache BEGIN SELECT RAISE(ABORT, 'disk simulation'); END",
      );
      await expectLater(
        repository.refreshArticles('61'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await repository.cachedArticles('61'))!.single.htmlBody,
        original.htmlBody,
      );
    },
  );

  test(
    'concurrent refreshes share a request; a captured reader snapshot is immutable',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final api = LegacyApi(
        client: MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
      addTearDown(api.close);
      final repository = LibraryRepository(database, api);
      final first = repository.refreshArticles('61');
      final second = repository.refreshArticles('61');
      pending.complete(apiResponse([articleJson()]));
      final results = await Future.wait([first, second]);
      expect(calls, 1);
      expect(results[0].single.htmlBody, results[1].single.htmlBody);
    },
  );

  test(
    'v1 database upgrades without losing notes, history or outbox',
    () async {
      final first = await database.save(
        Note.empty().copyWith(body: 'نسخهٔ پیشین'),
      );
      await database.save(first.copyWith(body: 'نسخهٔ فعلی'));
      // Reconstruct the v1 schema: v2 only adds the independent cache table.
      await database.db.execute('DROP TABLE library_cache');
      await database.db.execute(
        'ALTER TABLE notes DROP COLUMN rich_text_delta',
      );
      await database.db.setVersion(1);
      await database.close();
      database = await NotebookDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      expect(await database.db.getVersion(), 6);
      expect((await database.note(first.id))!.body, 'نسخهٔ فعلی');
      expect((await database.versions(first.id)).single.body, 'نسخهٔ پیشین');
      expect(await database.pendingCount(), 1);
      expect(await database.db.query('library_cache'), isEmpty);
    },
  );

  test(
    'empty categories are cached, and caches are scoped to the API source',
    () async {
      final api = LegacyApi(
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      final other = LegacyApi(
        endpoint: Uri.parse('https://example.com/api.php'),
      );
      addTearDown(api.close);
      addTearDown(other.close);
      final repository = LibraryRepository(database, api);
      expect(await repository.cachedArticles('61'), isNull);
      await repository.refreshArticles('61');
      expect(await repository.cachedArticles('61'), isEmpty);
      expect(
        await LibraryRepository(database, other).cachedArticles('61'),
        isNull,
      );
    },
  );
}
