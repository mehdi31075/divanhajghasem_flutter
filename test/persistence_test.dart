import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/note.dart';

void main() {
  sqfliteFfiInit();
  late Directory folder;
  late String path;
  late NotebookDatabase database;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('hajqasem-test-');
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
    'notes and reading preferences survive closing and reopening without a server',
    () async {
      await database.db.insert('categories', {
        'id': 'cached-category',
        'name': 'دستهٔ دریافت‌شده',
      });
      final note = await database.save(
        Note.empty().copyWith(
          title: 'سلام حاج قاسم',
          body: 'متن آفلاین',
          categoryId: 'cached-category',
        ),
      );
      await database.setPreference('last_note', note.id);
      await database.setPreference('scroll:${note.id}', '240');
      await database.close();
      database = await NotebookDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      expect((await database.note(note.id))?.body, 'متن آفلاین');
      expect(await database.preference('last_note'), note.id);
      expect(await database.preference('scroll:${note.id}'), '240');
      expect(await database.pendingCount(), 1);
    },
  );

  test(
    'a failed outbox write rolls back the note and its version atomically',
    () async {
      final first = await database.save(Note.empty().copyWith(body: 'متن اول'));
      await database.db.execute(
        "CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'disk simulation'); END",
      );
      await expectLater(
        database.save(first.copyWith(body: 'متن دوم')),
        throwsA(isA<DatabaseException>()),
      );
      expect((await database.note(first.id))?.body, 'متن اول');
      expect(await database.versions(first.id), isEmpty);
    },
  );

  test(
    'rapid queued edits keep the latest text and a late acknowledgement cannot remove it',
    () async {
      final controller = NotebookController(database);
      await controller.load();
      final draft = Note.empty();
      final writes = [
        for (var i = 1; i <= 30; i++)
          controller.save(draft.copyWith(body: 'نوشته $i')),
      ];
      final saved = await Future.wait(writes);
      expect((await database.note(draft.id))?.body, 'نوشته 30');
      expect((await database.note(draft.id))?.revision, 30);
      await database.acknowledge(draft.id, saved.first.revision);
      expect(await database.pendingCount(), 1);
      await database.acknowledge(draft.id, saved.last.revision);
      expect(await database.pendingCount(), 0);
      expect((await database.versions(draft.id)).length, 20);
      controller.dispose();
    },
  );

  test('trash preserves the content and restoration retains it', () async {
    final first = await database.save(
      Note.empty().copyWith(title: 'مجلس', body: 'نوشته محفوظ'),
    );
    final deleted = await database.save(first.copyWith(deleted: true));
    expect(await database.listNotes(), isEmpty);
    expect(
      (await database.listNotes(deleted: true)).single.body,
      'نوشته محفوظ',
    );
    await database.save(deleted.copyWith(deleted: false));
    expect((await database.listNotes()).single.body, 'نوشته محفوظ');
  });

  test(
    'one editor visit preserves a complete prior draft, not every keystroke',
    () async {
      final first = await database.save(
        Note.empty().copyWith(body: 'متن کامل قبلی'),
      );
      final session = newId();
      for (var i = 1; i <= 30; i++) {
        await database.save(
          first.copyWith(body: 'متن تازه $i'),
          editSession: session,
        );
      }
      final history = await database.versions(first.id);
      expect(history.length, 1);
      expect(history.single.body, 'متن کامل قبلی');
      expect((await database.note(first.id))?.body, 'متن تازه 30');
    },
  );
}
