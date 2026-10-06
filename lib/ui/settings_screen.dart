import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import 'history_screen.dart';
import 'notes_screen.dart';
import 'server_login_screen.dart';
import 'trash_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final NotebookController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTaps = 0;
  DateTime? _lastTap;
  bool _openingLogin = false;

  Future<void> _tapVersion() async {
    if (_openingLogin || widget.controller.isAdmin) return;
    final now = DateTime.now();
    if (_lastTap == null ||
        now.difference(_lastTap!) > const Duration(seconds: 3)) {
      _versionTaps = 0;
    }
    _lastTap = now;
    _versionTaps++;
    if (_versionTaps < 5) return;
    _versionTaps = 0;
    _openingLogin = true;
    try {
      await ensureServerLogin(context, widget.controller.posts.api);
    } finally {
      _openingLogin = false;
    }
  }

  Future<void> _openDrafts() async {
    await widget.controller.refreshNotes();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('پیش‌نویس‌های ادمین')),
          body: NotesScreen(controller: widget.controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PageBody(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اندازه متن مطالعه',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text('برای خواندن راحت‌تر'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    for (final item in const [
                      (20.0, 'معمولی'),
                      (24.0, 'درشت'),
                      (28.0, 'خیلی درشت'),
                    ])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: widget.controller.textSize == item.$1,
                        onSelected: (_) async {
                          try {
                            await widget.controller.setTextSize(item.$1);
                          } catch (_) {
                            if (context.mounted) showFailure(context);
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (widget.controller.isAdmin) ...[
          SoftMessage(
            title: 'مدیریت دیوان',
            message: 'امکانات ایجاد، ویرایش و حذف برای حساب مدیر فعال است.',
            icon: Icons.admin_panel_settings_outlined,
          ),
          ActionCard(
            title: 'پیش‌نویس‌های ادمین',
            subtitle: widget.controller.pendingCount > 0
                ? '${faDigits(widget.controller.pendingCount)} نوشته هنوز روی سرور ثبت نشده است.'
                : null,
            icon: Icons.edit_note,
            onTap: _openDrafts,
          ),
          ActionCard(
            title: 'یادداشت‌های حذف‌شده',
            icon: Icons.delete_outline,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => TrashScreen(controller: widget.controller),
              ),
            ),
          ),
          ActionCard(
            title: 'نسخه‌های قبلی نوشته‌ها',
            icon: Icons.history,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    HistoryNotesScreen(controller: widget.controller),
              ),
            ),
          ),
          OutlinedButton.icon(
            key: const Key('admin-logout'),
            onPressed: widget.controller.posts.api.logout,
            icon: const Icon(Icons.logout),
            label: const Text('خروج از مدیریت'),
          ),
        ],
        Center(
          child: InkWell(
            key: const Key('version-tap-target'),
            onTap: _tapVersion,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'دیوان · نسخهٔ ۰.۱.۰',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: NotebookColors.muted),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
