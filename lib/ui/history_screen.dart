import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import '../domain/note.dart';
import '../domain/library.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.note,
  });
  final NotebookController controller;
  final Note note;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<NoteVersion>> _versions;
  @override
  void initState() {
    super.initState();
    _versions = widget.controller.database.versions(widget.note.id);
  }

  Future<void> _preview(NoteVersion version) async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نسخه قبلی'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(version.title),
              const SizedBox(height: 16),
              Text(
                version.snapshot?.bodyIsHtml == true
                    ? plainHtml(version.body)
                    : version.body,
                style: const TextStyle(
                  fontSize: NotebookTypeScale.body,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('این نسخه را برگردان'),
          ),
        ],
      ),
    );
    if (restore != true || !mounted) {
      return;
    }
    try {
      final current = await widget.controller.database.note(widget.note.id);
      if (current == null) {
        return;
      }
      await widget.controller.save(
        current.copyWith(
          title: version.title,
          body: version.body,
          subtitle: version.snapshot?.subtitle,
          bodyIsHtml: version.snapshot?.bodyIsHtml ?? false,
          richTextDelta: version.snapshot?.richTextDelta,
          clearRichText: version.snapshot?.richTextDelta == null,
        ),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showFailure(context, 'نسخه قبلی برنگشت؛ متن فعلی حفظ شده است.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('نسخه‌های قبلی')),
    body: FutureBuilder<List<NoteVersion>>(
      future: _versions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return PageBody(
            children: [
              const SoftMessage(
                title: 'نسخه‌ها باز نشد',
                message: 'دوباره تلاش کنید.',
                isError: true,
              ),
              FilledButton(
                onPressed: () => setState(() {
                  _versions = widget.controller.database.versions(
                    widget.note.id,
                  );
                }),
                child: const Text('دوباره تلاش کن'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final versions = snapshot.data!;
        return PageBody(
          children: [
            const Text('برای دیدن یا برگرداندن متن، یک نسخه را باز کنید.'),
            if (versions.isEmpty)
              const SoftMessage(
                title: 'نسخه قبلی نداریم',
                message: 'پس از ویرایش متن، نسخه قبلی اینجا نگهداری می‌شود.',
                icon: Icons.history,
              ),
            for (final version in versions)
              ActionCard(
                title: version.title.isEmpty
                    ? 'یادداشت بی‌عنوان'
                    : version.title,
                subtitle:
                    '${widget.controller.dateService.relativeDate(version.createdAt)} · ${faDigits(version.createdAt.hour.toString().padLeft(2, '0'))}:${faDigits(version.createdAt.minute.toString().padLeft(2, '0'))}',
                icon: Icons.history,
                onTap: () => _preview(version),
              ),
          ],
        );
      },
    ),
  );
}

class HistoryNotesScreen extends StatelessWidget {
  const HistoryNotesScreen({super.key, required this.controller});
  final NotebookController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('نسخه‌های قبلی نوشته‌ها')),
    body: PageBody(
      children: [
        if (controller.notes.isEmpty)
          const SoftMessage(
            title: 'دفتر هنوز خالی است',
            message:
                'بعد از نوشتن و ویرایش، نسخه‌های قبلی در دسترس خواهند بود.',
          ),
        for (final note in controller.notes)
          ActionCard(
            title: note.displayTitle,
            icon: Icons.history,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    HistoryScreen(controller: controller, note: note),
              ),
            ),
          ),
      ],
    ),
  );
}
