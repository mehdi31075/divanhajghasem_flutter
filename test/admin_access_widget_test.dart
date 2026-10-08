import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/post_api.dart';
import 'package:hajqasem_app/domain/library.dart';
import 'package:hajqasem_app/main.dart';
import 'package:hajqasem_app/ui/library_reader_screen.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('the public app has no admin login or content actions', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => NotebookDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    var loginRequests = 0;
    final api = PostApi(
      Uri.parse('http://example.test/api.php'),
      client: MockClient((request) async {
        loginRequests++;
        throw StateError('The public app must not request admin login.');
      }),
    );
    final controller = NotebookController(
      db,
      api: LegacyApi(
        client: MockClient((_) async => http.Response('[]', 200)),
      ),
      postApi: api,
    );
    await tester.runAsync(controller.load);
    await tester.pumpWidget(HajQasemApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes-tab')), findsNothing);
    expect(find.byKey(const Key('new-note')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-tab')));
    await tester.pumpAndSettle();
    expect(find.text('پیش‌نویس‌های ادمین'), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('version-tap-target')));
      await tester.pump();
    }
    expect(find.text('ورود'), findsNothing);
    expect(loginRequests, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(db.close);
  });

  testWidgets('reader never exposes server edit or delete actions', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => NotebookDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = NotebookController(
      db,
      api: LegacyApi(client: MockClient((_) async => http.Response('[]', 200))),
    );
    const article = LibraryArticle(
      id: '7',
      categoryId: '61',
      title: 'نمونه',
      subtitle: 'زیرعنوان',
      htmlBody: '<p>متن</p>',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryReaderScreen(controller: controller, article: article),
      ),
    );
    await tester.runAsync(() => db.preference('ready'));
    await tester.pumpAndSettle();
    expect(find.text('نمونه'), findsOneWidget);
    expect(find.byKey(const Key('edit-post')), findsNothing);
    expect(find.byKey(const Key('delete-post')), findsNothing);
    controller.posts.api.authenticated = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-post')), findsNothing);
    expect(find.byKey(const Key('delete-post')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(db.close);
  });
}
