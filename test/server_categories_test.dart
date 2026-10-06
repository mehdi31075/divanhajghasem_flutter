import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'legacy_api_test.dart' show apiResponse, categoryJson;

void main() {
  sqfliteFfiInit();
  late Directory folder;
  late NotebookDatabase database;
  late NotebookController controller;
  late String path;
  late bool online;
  late List<Map<String, Object>> rows;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('divan-categories-');
    path = '${folder.path}/notebook.db';
    database = await NotebookDatabase.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    online = true;
    rows = [categoryJson()];
    controller = NotebookController(
      database,
      api: LegacyApi(
        client: MockClient((_) async {
          if (!online) throw const SocketException('offline');
          return apiResponse(rows);
        }),
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
    await folder.delete(recursive: true);
  });

  test('fresh offline install has no invented categories', () async {
    online = false;
    await controller.load();
    expect(await database.categories(), isEmpty);
    expect(controller.categories, isEmpty);
    await expectLater(
      controller.refreshCategories(),
      throwsA(isA<SocketException>()),
    );
    expect(controller.categories, isEmpty);
    expect(await controller.cachedCategories(), isNull);
  });

  test(
    'server owns the list; offline and removed categories preserve notes',
    () async {
      await controller.load();
      await controller.refreshCategories();
      final category = controller.categories.single;
      final note = await controller.save(
        Note.empty().copyWith(body: 'نوشتهٔ محفوظ', categoryId: category.id),
      );
      rows = [
        {...categoryJson(), 'category_name': 'نام تازه از سرور'},
        {...categoryJson(), 'cid': '62', 'category_name': 'نام تازه از سرور'},
      ];
      await controller.refreshCategories();
      expect(controller.categories, hasLength(2));
      expect(controller.categoryName(note.categoryId), 'نام تازه از سرور');
      online = false;
      await expectLater(
        controller.refreshCategories(),
        throwsA(isA<SocketException>()),
      );
      await controller.load();
      expect(controller.categories, hasLength(2));
      online = true;
      rows = [];
      await controller.refreshCategories();
      expect(controller.categories, isEmpty);
      expect((await database.note(note.id))!.categoryId, category.id);
      expect((await database.note(note.id))!.body, 'نوشتهٔ محفوظ');
      expect(await database.pendingCount(), 1);
      expect(await database.versions(note.id), isEmpty);
      expect(await database.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'category cache and note references roll back together on disk failure',
    () async {
      await controller.refreshCategories();
      rows = [
        {...categoryJson(), 'category_name': 'تغییر نباید ثبت شود'},
      ];
      await database.db.execute(
        "CREATE TRIGGER fail_categories BEFORE INSERT ON library_cache BEGIN SELECT RAISE(ABORT, 'disk simulation'); END",
      );
      await expectLater(
        controller.refreshCategories(),
        throwsA(isA<DatabaseException>()),
      );
      expect(controller.categories.single.name, 'دستهٔ فارسی');
      expect((await database.categories()).single.name, 'دستهٔ فارسی');
      expect((await controller.cachedCategories())!.single.name, 'دستهٔ فارسی');
    },
  );

  test(
    'v2 migration preserves drafts, trash, history and pending writes',
    () async {
      await database.db.insert('categories', {
        'id': 'prayer',
        'name': 'مدح و مناجات',
      });
      await database.db.insert('categories', {
        'id': 'events',
        'name': 'مناسبت‌ها',
      });
      await database.db.execute(
        'CREATE UNIQUE INDEX old_category_names ON categories(name)',
      );
      final original = await database.save(
        Note.empty().copyWith(
          title: 'عنوان',
          body: 'نسخهٔ قبل',
          categoryId: 'prayer',
        ),
      );
      final updated = await database.save(original.copyWith(body: 'متن فعلی'));
      final trashed = await database.save(
        Note.empty().copyWith(
          body: 'یادداشت حذف‌شده',
          categoryId: 'prayer',
          deleted: true,
        ),
      );
      await controller.library.refreshCategories();
      final outbox = await database.db.query('outbox', orderBy: 'note_id');
      await database.db.execute(
        'ALTER TABLE notes DROP COLUMN rich_text_delta',
      );
      await database.db.setVersion(2);
      controller.dispose();
      await database.close();
      database = await NotebookDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      controller = NotebookController(
        database,
        api: LegacyApi(
          client: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
      );
      await controller.load();
      expect(await database.db.getVersion(), 6);
      expect(controller.categories.map((category) => category.name), [
        'دستهٔ فارسی',
      ]);
      expect(
        (await database.categories()).any(
          (category) => category.id == 'events',
        ),
        isFalse,
      );
      expect((await database.note(updated.id))!.toMap(), updated.toMap());
      expect((await database.note(trashed.id))!.toMap(), trashed.toMap());
      expect((await database.versions(updated.id)).single.body, 'نسخهٔ قبل');
      expect(await database.db.query('outbox', orderBy: 'note_id'), outbox);
      expect(await database.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
        database.save(Note.empty().copyWith(categoryId: 'missing')),
        throwsA(isA<DatabaseException>()),
      );
      final saved = await controller.save(
        updated.copyWith(categoryId: controller.categories.single.id),
      );
      expect(saved.body, 'متن فعلی');
    },
  );
}
