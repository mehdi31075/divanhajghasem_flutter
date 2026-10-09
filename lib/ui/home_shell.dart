import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import 'categories_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'content_page_screen.dart';
import 'support_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final NotebookController controller;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _categoriesVisited = false;
  bool _supportVisited = false;

  void _selectTab(int value) {
    setState(() {
      _tab = value;
      if (value == 1) _categoriesVisited = true;
      if (value == 2) _supportVisited = true;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(['دیوان انصارالحسین(ع)', 'دسته‌بندی‌ها', 'پشتیبانی', 'تنظیمات'][_tab]),
      ),
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
          if (_supportVisited)
            SupportScreen(controller: widget.controller)
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
            key: Key('support-tab'),
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'پشتیبانی',
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
                  'به دیوان انصارالحسین(ع) خوش آمدید',
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
        title: 'دسته‌بندی‌ها و مطالب دیوان انصارالحسین(ع)',
        subtitle: 'از میان دسته‌های تصویری انتخاب کنید',
        icon: Icons.auto_stories_outlined,
        onTap: onCategories,
      ),
      for (final page in const [
        ('first-talk', 'سخن اول', Icons.bookmark_border),
        ('last-talk', 'سخن آخر', Icons.menu_book_outlined),
        ('contact', 'تماس با ما', Icons.mail_outline),
      ])
        ActionCard(
          key: Key('page-${page.$1}'),
          title: page.$2,
          icon: page.$3,
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ContentPageScreen(
                controller: controller,
                slug: page.$1,
                label: page.$2,
              ),
            ),
          ),
        ),
      const SoftMessage(
        title: 'مطالعهٔ دیوان انصارالحسین(ع)',
        message:
            'مطالب از دیوان انصارالحسین(ع) بارگذاری می‌شوند و پس از باز شدن، برای مطالعهٔ بدون اینترنت هم در دسترس‌اند.',
        icon: Icons.auto_stories_outlined,
      ),
    ],
  );
}
