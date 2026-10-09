import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import '../domain/note.dart';
import '../domain/library.dart';
import 'editor_screen.dart';
import 'reader_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _normalize(String text) =>
    text.replaceAll('ي', 'ی').replaceAll('ك', 'ک').toLowerCase();

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.controller,
    this.categoryId,
    this.uncategorized = false,
  });
  final NotebookController controller;
  final String? categoryId;
  final bool uncategorized;
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _query = '';
  bool _favorites = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final notes = widget.controller.notes
          .where(
            (n) =>
                (!widget.uncategorized || n.categoryId == null) &&
                (widget.categoryId == null ||
                    n.categoryId == widget.categoryId) &&
                (!_favorites || n.favorite) &&
                _normalize(
                  '${n.title}\n${n.body}',
                ).contains(_normalize(_query)),
          )
          .toList();
      return PageBody(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'جستجو در یادداشت‌ها...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('همه یادداشت‌ها'),
                selected: !_favorites,
                onSelected: (_) => setState(() => _favorites = false),
              ),
              FilterChip(
                label: const Text('نشان‌شده‌ها'),
                selected: _favorites,
                onSelected: (_) => setState(() => _favorites = true),
              ),
            ],
          ),
          if (notes.isEmpty)
            SoftMessage(
              title: _query.isEmpty ? 'پیش‌نویسی ندارید' : 'نوشته‌ای پیدا نشد',
              message: _query.isEmpty
                  ? 'نوشته‌های ذخیره‌نشده اینجا می‌مانند. پس از ذخیرهٔ مطلب، آن را در «دسته‌بندی‌ها» می‌بینید.'
                  : 'با واژه دیگری جستجو کنید.',
              icon: Icons.menu_book_outlined,
            ),
          for (final note in notes)
            NoteCard(
              note: note,
              controller: widget.controller,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReaderScreen(
                    controller: widget.controller,
                    initial: note,
                  ),
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => EditorScreen(
                  controller: widget.controller,
                  initial: Note.empty().copyWith(categoryId: widget.categoryId),
                ),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('یادداشت تازه'),
          ),
        ],
      );
    },
  );
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.controller,
    required this.onTap,
  });
  final Note note;
  final NotebookController controller;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.categoryName(note.categoryId),
              style: const TextStyle(
                fontSize: NotebookTypeScale.small,
                color: NotebookColors.gold,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (note.favorite)
                  const Icon(Icons.star, color: NotebookColors.gold),
              ],
            ),
            Text(
              note.body.isEmpty
                  ? 'هنوز متنی نوشته نشده'
                  : note.bodyIsHtml
                  ? plainHtml(note.body)
                  : note.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: NotebookTypeScale.small,
                color: NotebookColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${controller.dateService.relativeDate(note.updatedAt)} · پیش‌نویس روی گوشی',
              style: const TextStyle(
                fontSize: NotebookTypeScale.small,
                color: NotebookColors.teal,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
