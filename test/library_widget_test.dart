import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/library.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'package:hajqasem_app/main.dart';
import 'package:hajqasem_app/ui/editor_screen.dart';
import 'package:hajqasem_app/ui/library_reader_screen.dart';
import 'package:hajqasem_app/ui/library_screen.dart';
import 'package:hajqasem_app/ui/theme.dart';
import 'legacy_api_test.dart' show apiResponse, articleJson, categoryJson;

Widget app(Widget home) => MaterialApp(
  locale: const Locale('fa'),
  supportedLocales: const [Locale('fa')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: notebookTheme(),
  home: home,
);

void main() {
  sqfliteFfiInit();

  testWidgets(
    'category tab shows server images, keeps search and opens the selected category',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final requests = <Uri>[];
      final db = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = NotebookController(
        db,
        api: LegacyApi(
          client: MockClient((request) async {
            requests.add(request.url);
            return apiResponse(
              request.url.queryParameters.isEmpty
                  ? [
                      categoryJson(),
                      {
                        ...categoryJson(),
                        'cid': '62',
                        'category_name': 'دستهٔ دوم',
                      },
                    ]
                  : [
                      {...articleJson(), 'cat_id': '62'},
                    ],
            );
          }),
        ),
      );
      await tester.runAsync(controller.load);
      await tester.runAsync(controller.refreshCategories);
      await tester.pumpWidget(HajQasemApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categories-tab')));
      await tester.pump();
      await tester.runAsync(controller.cachedCategories);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(requests.length, greaterThan(1)); // Opening refreshes the API.
      final firstCard = find.byKey(const ValueKey('category-61'));
      final secondCard = find.byKey(const ValueKey('category-62'));
      expect(tester.getTopLeft(firstCard).dy, tester.getTopLeft(secondCard).dy);
      final image = tester.widget<Image>(
        find.descendant(of: firstCard, matching: find.byType(Image)),
      );
      expect(
        (image.image as NetworkImage).url,
        'http://divanhajghasem.ir/upload/category/cover.png',
      );

      await tester.enterText(find.byType(TextField), 'دوم');
      await tester.pumpAndSettle();
      expect(firstCard, findsNothing);
      await tester.tap(find.byKey(const Key('settings-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categories-tab')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text ??
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
        'دوم',
      );
      expect(firstCard, findsNothing);
      await tester.tap(secondCard);
      await tester.pump();
      await tester.runAsync(() => db.preference('barrier'));
      await tester.runAsync(() => controller.library.refreshArticles('62'));
      await tester.pumpAndSettle();
      expect(find.text('عنوان فارسی'), findsOneWidget);
      expect(find.byKey(const Key('new-category-post')), findsNothing);
      expect(requests.last.queryParameters['cat_id'], '62');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        secondCard,
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(secondCard).width, 288);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
      controller.dispose();
    },
  );

  test(
    'reading HTML preserves paragraphs, emphasis and breaks while allowing large fonts',
    () {
      final content = readableHtml(
        '<p style="font-size:10px;text-align:center"><strong>متن</strong><br>دوم</p>'
        '<script>ignored</script><img src="file:///private/example"><img src="upload/a.png">',
        Uri.parse('http://divanhajghasem.ir/api.php'),
      );
      final document = html.parseFragment(content);
      expect(document.querySelector('strong')!.text, 'متن');
      expect(document.querySelectorAll('br'), hasLength(1));
      expect(content, contains('text-align:center'));
      expect(content, isNot(contains('font-size')));
      expect(content, isNot(contains('script')));
      expect(content, isNot(contains('file:')));
      expect(content, contains('http://divanhajghasem.ir/upload/a.png'));
    },
  );

  testWidgets(
    'open reader stays on its snapshot after cache refresh and fits large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var body = '<p>متن پیشین<br><strong>ادامهٔ متن</strong></p>';
      final api = LegacyApi(
        client: MockClient((_) async => apiResponse([articleJson(body: body)])),
      );
      final db = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = NotebookController(db, api: api);
      await tester.runAsync(controller.load);
      final articles = (await tester.runAsync(
        () => controller.library.refreshArticles('61'),
      ))!;
      await tester.pumpWidget(
        app(
          LibraryReaderScreen(controller: controller, article: articles.single),
        ),
      );
      await tester.runAsync(() => db.preference('barrier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html,
        contains('متن پیشین'),
      );
      body = '<p>متن تازه از سایت</p>';
      await tester.runAsync(() => controller.library.refreshArticles('61'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html,
        isNot(contains('متن تازه')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
      controller.dispose();
    },
  );

  testWidgets(
    'server categories arrive during editing without replacing the draft',
    (tester) async {
      final pending = Completer<http.Response>();
      final db = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      await tester.runAsync(
        () => db.db.insert('categories', {
          'id': 'old-category',
          'name': 'دستهٔ قدیمی',
        }),
      );
      final note = (await tester.runAsync(
        () => db.save(
          Note.empty().copyWith(
            title: 'عنوان پیشین',
            body: 'متن محفوظ',
            categoryId: 'old-category',
          ),
        ),
      ))!;
      final controller = NotebookController(
        db,
        api: LegacyApi(client: MockClient((_) => pending.future)),
      );
      await tester.runAsync(controller.load);
      await tester.pumpWidget(
        app(EditorScreen(controller: controller, initial: note)),
      );
      await tester.runAsync(() => db.preference('barrier'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('note-title')),
        'عنوان در حال نوشتن',
      );
      await tester.runAsync(controller.flush);
      await tester.runAsync(() async {
        pending.complete(apiResponse([categoryJson()]));
        await controller.refreshCategories();
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('note-title')))
            .controller!
            .text,
        'عنوان در حال نوشتن',
      );
      expect(
        (await tester.runAsync(() => db.note(note.id)))!.categoryId,
        'old-category',
      );
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('دستهٔ فارسی').last);
      await tester.pumpAndSettle();
      await tester.runAsync(controller.flush);
      final saved = (await tester.runAsync(() => db.note(note.id)))!;
      expect(saved.categoryId, controller.categories.single.id);
      expect(saved.title, 'عنوان در حال نوشتن');
      expect(saved.body, 'متن محفوظ');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
      controller.dispose();
    },
  );

  testWidgets(
    'cached article list stays visible after automatic refresh fails',
    (tester) async {
      var online = true;
      var calls = 0;
      final api = LegacyApi(
        client: MockClient((_) async {
          calls++;
          if (!online) throw const SocketException('offline');
          return apiResponse([articleJson()]);
        }),
      );
      final db = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = NotebookController(db, api: api);
      await tester.runAsync(controller.load);
      await tester.runAsync(() => controller.library.refreshArticles('61'));
      online = false;
      await tester.pumpWidget(
        app(
          LibraryArticlesScreen(
            controller: controller,
            category: const LibraryCategory(id: '61', name: 'دستهٔ فارسی'),
          ),
        ),
      );
      await tester.runAsync(() => db.preference('barrier'));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(1)); // Opening checks the API again.
      expect(find.text('عنوان فارسی'), findsOneWidget);
      await tester.tap(find.text('دوباره تلاش کن'));
      await tester.pumpAndSettle();
      expect(find.text('بارگذاری انجام نشد'), findsOneWidget);
      expect(find.text('عنوان فارسی'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(db.close);
      controller.dispose();
    },
  );
}
