import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'application/notebook_controller.dart';
import 'data/notebook_database.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotebookBootstrap());
}

class NotebookBootstrap extends StatefulWidget {
  const NotebookBootstrap({super.key});
  @override
  State<NotebookBootstrap> createState() => _NotebookBootstrapState();
}

class _NotebookBootstrapState extends State<NotebookBootstrap> {
  late Future<NotebookController> _startup;
  @override
  void initState() {
    super.initState();
    _startup = _open();
  }

  Future<NotebookController> _open() async {
    final database = await NotebookDatabase.open();
    final controller = NotebookController(database);
    try {
      await controller.load();
      return controller;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<NotebookController>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return HajQasemApp(controller: snapshot.data!);
      }
      return MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: notebookTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'دفتر باز نشد. نوشته‌های ذخیره‌شده پاک نشده‌اند.',
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => setState(() {
                            _startup = _open();
                          }),
                          child: const Text('دوباره تلاش کن'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}

class HajQasemApp extends StatelessWidget {
  const HajQasemApp({super.key, required this.controller});
  final NotebookController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'دیوان',
    theme: notebookTheme(),
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    home: HomeShell(controller: controller),
  );
}
