import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/library_repository.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'package:hajqasem_app/main.dart';
import 'package:hajqasem_app/ui/content_page_screen.dart';

List<Map<String, Object>> pages({
  String body = '<p>متن سرور</p>',
  int revision = 1,
}) => [
  for (final slug in ['first-talk', 'last-talk', 'contact'])
    {
      'slug': slug,
      'title': 'عنوان $slug',
      'html_body': body,
      'revision': revision,
      'updated_at': '2026-10-07T00:00:00Z',
    },
];
http.Response response(List<Map<String, Object>> records) =>
    http.Response.bytes(utf8.encode(jsonEncode({'pages': records})), 200);

void main() {
  sqfliteFfiInit();
  test(
    'public pages use a separate endpoint and reject missing or duplicate records',
    () async {
      var records = pages();
      final api = LegacyApi(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://divanhajghasem.ir/index.php/pages.php',
          );
          expect(request.headers.containsKey('authorization'), false);
          return response(records);
        }),
      );
      addTearDown(api.close);
      expect((await api.pages()).length, 3);
      records = [pages().first];
      await expectLater(api.pages(), throwsFormatException);
      records = [pages().first, pages().first, pages().last];
      await expectLater(api.pages(), throwsFormatException);
    },
  );

  test(
    'pages survive restart and failed refresh without overwriting drafts',
    () async {
      final folder = await Directory.systemTemp.createTemp('divan-pages-');
      var db = await NotebookDatabase.open(
        path: '${folder.path}/db',
        factory: databaseFactoryFfi,
      );
      var online = true;
      final api = LegacyApi(
        client: MockClient((_) async {
          if (!online) throw const SocketException('offline');
          return response(pages());
        }),
      );
      try {
        final note = await db.save(
          Note.empty().copyWith(body: 'پیش‌نویس محفوظ'),
        );
        await LibraryRepository(db, api).refreshPages();
        await db.close();
        db = await NotebookDatabase.open(
          path: '${folder.path}/db',
          factory: databaseFactoryFfi,
        );
        online = false;
        final library = LibraryRepository(db, api);
        await expectLater(
          library.refreshPages(),
          throwsA(isA<SocketException>()),
        );
        expect(
          (await library.cachedPages())!.first.htmlBody,
          '<p>متن سرور</p>',
        );
        expect((await db.note(note.id))!.body, 'پیش‌نویس محفوظ');
        expect(await db.pendingCount(), 1);
      } finally {
        await db.close();
        api.close();
        await folder.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'all three pages are available to the public from the home screen',
    (tester) async {
      final db = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = NotebookController(
        db,
        api: LegacyApi(client: MockClient((_) async => response(pages()))),
      );
      await tester.runAsync(controller.load);
      await tester.pumpWidget(HajQasemApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('publish-post')), findsNothing);
      expect(find.text('پیش‌نویس‌های ادمین'), findsNothing);
      for (final slug in ['first-talk', 'last-talk', 'contact']) {
        final card = find.byKey(Key('page-$slug'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pump();
        await tester.runAsync(controller.library.refreshPages);
        await tester.pumpAndSettle();
        expect(find.text('عنوان $slug'), findsOneWidget);
        Navigator.of(tester.element(find.byType(ContentPageScreen))).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(db.close);
    },
  );
}
