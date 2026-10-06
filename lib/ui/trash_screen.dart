import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import '../domain/note.dart';
import 'widgets.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.controller});
  final NotebookController controller;
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late Future<List<Note>> _notes;
  @override
  void initState() {
    super.initState();
    _notes = widget.controller.database.listNotes(deleted: true);
  }

  Future<void> _restore(Note note) async {
    if (!await confirm(
      context,
      'برگرداندن یادداشت؟',
      note.displayTitle,
      action: 'برگردان',
    )) {
      return;
    }
    try {
      await widget.controller.save(note.copyWith(deleted: false));
      if (mounted) {
        setState(() {
          _notes = widget.controller.database.listNotes(deleted: true);
        });
      }
    } catch (_) {
      if (mounted) {
        showFailure(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('یادداشت‌های حذف‌شده')),
    body: FutureBuilder<List<Note>>(
      future: _notes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return PageBody(
            children: [
              const SoftMessage(
                title: 'فهرست باز نشد',
                message: 'دوباره تلاش کنید.',
                isError: true,
              ),
              FilledButton(
                onPressed: () => setState(() {
                  _notes = widget.controller.database.listNotes(deleted: true);
                }),
                child: const Text('دوباره تلاش کن'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notes = snapshot.data!;
        return PageBody(
          children: [
            const Text(
              'یادداشت‌ها پاک نشده‌اند؛ با لمس هرکدام آن را برگردانید.',
            ),
            if (notes.isEmpty)
              const SoftMessage(
                title: 'یادداشت حذف‌شده‌ای نیست',
                message: 'نوشته‌های حذف‌شده اینجا نگهداری می‌شوند.',
              ),
            for (final note in notes)
              ActionCard(
                title: note.displayTitle,
                subtitle: 'لمس کنید تا برگردد',
                icon: Icons.restore,
                onTap: () => _restore(note),
              ),
          ],
        );
      },
    ),
  );
}
