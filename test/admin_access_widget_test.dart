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
import 'package:hajqasem_app/ui/server_login_screen.dart';

void main() {
  sqfliteFfiInit();

  testWidgets(
    'five version taps unlock preview without PHP auth and logout locks it',
    (tester) async {
      final db = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      var loginPosts = 0;
      var logouts = 0;
      final api = PostApi(
        Uri.parse('http://example.test/api.php'),
        client: MockClient((request) async {
          if (request.method == 'POST' && request.url.path == '/index.php') {
            loginPosts++;
            expect(request.bodyFields, {
              'username': 'admin-test',
              'password': 'dummy-password',
              'btnLogin': '1',
            });
            return http.Response('', 302);
          }
          if (request.url.path == '/add-menu.php') {
            return http.Response(
              '<form><button name="btnAdd">Add</button></form>',
              200,
            );
          }
          if (request.url.path == '/logout.php') {
            logouts++;
            return http.Response('', 200);
          }
          throw StateError('Unexpected panel request: ${request.url}');
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
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('version-tap-target')));
        await tester.pump();
      }
      expect(find.byType(ServerLoginScreen), findsNothing);
      await tester.tap(find.byKey(const Key('version-tap-target')));
      await tester.pumpAndSettle();
      expect(find.byType(ServerLoginScreen), findsOneWidget);
      await tester.enterText(find.byKey(const Key('server-username')), 'admin');
      await tester.enterText(
        find.byKey(const Key('server-password')),
        const String.fromEnvironment('DIVAN_PREVIEW_PASSWORD'),
      );
      await tester.tap(find.text('ورود'));
      await tester.pumpAndSettle();
      expect(loginPosts, 0);
      expect(api.authenticated, isFalse);
      expect(api.localPreviewAdmin, isTrue);
      expect(controller.isAdmin, isTrue);
      expect(find.text('پیش‌نویس‌های ادمین'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('admin-logout')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('admin-logout')));
      await tester.pumpAndSettle();
      expect(logouts, 0);
      expect(controller.isAdmin, isFalse);
      expect(find.text('پیش‌نویس‌های ادمین'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(db.close);
    },
  );

  testWidgets('reader management buttons follow authenticated admin state', (
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
    expect(find.byKey(const Key('edit-post')), findsOneWidget);
    expect(find.byKey(const Key('delete-post')), findsOneWidget);
    controller.posts.api.authenticated = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-post')), findsNothing);
    expect(find.byKey(const Key('delete-post')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(db.close);
  });
}
