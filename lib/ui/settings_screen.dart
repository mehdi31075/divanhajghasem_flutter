import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import 'account_login_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final NotebookController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _openAccount() async {
    if (widget.controller.isSignedIn) {
      final logout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('حساب کاربری'),
          content: Text(
            widget.controller.accountUser?['name']?.toString() ??
                'شمارهٔ تأییدشده: ${widget.controller.accountUser?['mobile'] ?? ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('بستن'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('خروج از حساب'),
            ),
          ],
        ),
      );
      if (logout == true) await widget.controller.logoutAccount();
      return;
    }
    await showDialog<bool>(
      context: context,
      builder: (_) => AccountLoginDialog(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PageBody(
      children: [
        Card(
          child: ListTile(
            key: const Key('app-account'),
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(
              widget.controller.isSignedIn
                  ? 'حساب کاربری'
                  : 'ورود یا ساخت حساب',
            ),
            subtitle: Text(
              widget.controller.isSignedIn
                  ? '${widget.controller.accountUser?['name'] ?? widget.controller.accountUser?['mobile'] ?? 'وارد شده'}'
                  : 'با شمارهٔ موبایل وارد شوید تا حساب شما در اپ فعال شود.',
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: _openAccount,
          ),
        ),
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
        Center(
          child: InkWell(
            key: const Key('version-tap-target'),
            onTap: null,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'دیوان انصارالحسین(ع) · نسخهٔ ۰.۱.۰',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: NotebookTypeScale.small,
                  color: NotebookColors.muted,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
