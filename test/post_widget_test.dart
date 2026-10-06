import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/post_api.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'package:hajqasem_app/ui/editor_screen.dart';
import 'package:hajqasem_app/ui/server_login_screen.dart';
import 'package:hajqasem_app/ui/theme.dart';
import 'post_service_test.dart' show FakePhp;

void main() {
  sqfliteFfiInit();
  for (final scenario in ['incomplete', 'login', 'unconfirmed', 'success']) {
    testWidgets(
      'editor $scenario stays inside the app and preserves required draft state',
      (tester) async {
        final server = FakePhp()..ignorePost = scenario == 'unconfirmed';
        final database = (await tester.runAsync(
          () => NotebookDatabase.open(
            path: inMemoryDatabasePath,
            factory: databaseFactoryFfi,
          ),
        ))!;
        final controller = NotebookController(
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
        controller.posts.api.authenticated = scenario != 'login';
        await tester.runAsync(controller.refreshCategories);
        final note = (await tester.runAsync(
          () => controller.save(
            Note.empty().copyWith(
              title: 'عنوان تست',
              subtitle: scenario == 'incomplete' ? '' : 'زیرعنوان',
              body: 'متن محفوظ',
              categoryId: controller.library.noteCategoryId('61'),
            ),
          ),
        ))!;
        var published = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: notebookTheme(),
            locale: const Locale('fa'),
            supportedLocales: const [Locale('fa')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditorScreen(
                        controller: controller,
                        initial: note,
                        onPublished: () => published = true,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('publish-post')));
        for (var attempt = 0; attempt < 40; attempt++) {
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump();
          if (published ||
              find.byType(ServerLoginScreen).evaluate().isNotEmpty ||
              tester
                      .widget<FilledButton>(
                        find.byKey(const Key('publish-post')),
                      )
                      .onPressed !=
                  null) {
            break;
          }
        }
        await tester.pumpAndSettle();
        if (scenario == 'success') {
          expect(
            published,
            isTrue,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .join(' | '),
          );
          expect(find.byType(EditorScreen), findsNothing);
          expect(await tester.runAsync(() => database.note(note.id)), isNull);
        } else {
          expect(published, isFalse);
          expect(
            await tester.runAsync(() => database.note(note.id)),
            isNotNull,
          );
          if (scenario == 'login') {
            expect(find.byType(ServerLoginScreen), findsOneWidget);
            expect(server.posts, 0);
          } else if (scenario == 'incomplete') {
            expect(find.byType(ServerLoginScreen), findsNothing);
            expect(server.posts, 0);
          } else {
            expect(find.text('بررسی نتیجهٔ ارسال'), findsOneWidget);
            await tester.tap(find.byKey(const Key('publish-post')));
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            });
            await tester.pumpAndSettle();
            expect(server.posts, 1);
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(database.close);
      },
    );
  }
}
