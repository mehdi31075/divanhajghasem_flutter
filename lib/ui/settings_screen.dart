import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final NotebookController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
        Center(
          child: InkWell(
            key: const Key('version-tap-target'),
            onTap: null,
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
