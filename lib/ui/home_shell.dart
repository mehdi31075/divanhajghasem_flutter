import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import '../domain/note.dart';
import 'editor_screen.dart';
import 'categories_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final NotebookController controller;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _categoriesVisited = false;

  void _selectTab(int value) {
    setState(() {
      _tab = value;
      if (value == 1) _categoriesVisited = true;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(['دیوان', 'دسته‌بندی‌ها', 'تنظیمات'][_tab])),
      body: IndexedStack(
        index: _tab,
        children: [
          _Home(
            controller: widget.controller,
            onCategories: () => _selectTab(1),
          ),
          if (_categoriesVisited)
            CategoriesScreen(controller: widget.controller, embedded: true)
          else
            const SizedBox.shrink(),
          SettingsScreen(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 88,
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'خانه',
          ),
          NavigationDestination(
            key: Key('categories-tab'),
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'دسته‌بندی‌ها',
          ),
          NavigationDestination(
            key: Key('settings-tab'),
            icon: Icon(Icons.settings_outlined),
            label: 'تنظیمات',
          ),
        ],
      ),
    ),
  );
}

class _Home extends StatelessWidget {
  const _Home({required this.controller, required this.onCategories});
  final NotebookController controller;
  final VoidCallback onCategories;
  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'به دیوان خوش آمدید',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Text('دسته‌بندی‌ها و مطالب را مرور کنید.'),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NotebookColors.soft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.menu_book,
              color: NotebookColors.teal,
              size: 32,
            ),
          ),
        ],
      ),
      ActionCard(
        title: 'دسته‌بندی‌ها و مطالب دیوان',
        subtitle: 'از میان دسته‌های تصویری انتخاب کنید',
        icon: Icons.auto_stories_outlined,
        onTap: onCategories,
      ),
      if (controller.isAdmin)
        FilledButton.icon(
          key: const Key('new-note'),
          icon: const Icon(Icons.add),
          label: const Text('مطلب تازه'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  EditorScreen(controller: controller, initial: Note.empty()),
            ),
          ),
        ),
      const SoftMessage(
        title: 'مطالعهٔ دیوان',
        message:
            'مطالب از دیوان بارگذاری می‌شوند و پس از باز شدن، برای مطالعهٔ بدون اینترنت هم در دسترس‌اند.',
        icon: Icons.auto_stories_outlined,
      ),
    ],
  );
}
