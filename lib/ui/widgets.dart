import 'package:flutter/material.dart';
import 'theme.dart';

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
    key: key,
    padding: const EdgeInsets.all(24),
    children: [
      for (final child in children)
        Padding(padding: const EdgeInsets.only(bottom: 16), child: child),
    ],
  );
}

class SoftMessage extends StatelessWidget {
  const SoftMessage({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.check_circle_outline,
    this.isError = false,
  });
  final String title;
  final String message;
  final IconData icon;
  final bool isError;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFECEC) : NotebookColors.soft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: isError ? Colors.red.shade800 : NotebookColors.teal,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: isError ? Colors.red.shade800 : NotebookColors.teal,
                  ),
                ),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: NotebookColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      minTileHeight: 72,
      leading: Icon(icon, color: NotebookColors.teal, size: 28),
      title: Text(title, style: const TextStyle(fontSize: 20)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 16)),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

void showFailure(
  BuildContext context, [
  String message = 'انجام نشد. لطفاً دوباره تلاش کنید.',
]) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'بله، انجام بده',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
