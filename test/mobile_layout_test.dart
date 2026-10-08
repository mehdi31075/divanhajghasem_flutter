import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/main.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/notebook_database.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
    'public home stays RTL and fits a narrow screen with large system text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final database = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = NotebookController(
        database,
        api: LegacyApi(
          client: MockClient((_) async => http.Response('[]', 200)),
        ),
      );
      await tester.runAsync(controller.load);
      await tester.runAsync(controller.refreshCategories);
      await tester.pumpWidget(HajQasemApp(controller: controller));
      await tester.pumpAndSettle();
      final homeContext = tester.element(find.text('به دیوان خوش آمدید'));
      expect(Directionality.of(homeContext), TextDirection.rtl);
      expect(find.text('به دیوان خوش آمدید'), findsOneWidget);
      expect(find.byKey(const Key('new-note')), findsNothing);
      expect(tester.takeException(), isNull);
      controller.posts.api.authenticated = true;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-note')), findsNothing);
      expect(find.byKey(const Key('note-title')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(database.close);
      controller.dispose();
    },
  );
}
