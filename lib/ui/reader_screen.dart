import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../application/notebook_controller.dart';
import '../domain/note.dart';
import 'editor_screen.dart';
import 'history_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'library_reader_screen.dart' show readableHtml;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.controller,
    required this.initial,
  });
  final NotebookController controller;
  final Note initial;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late Note _note;
  late ScrollController _scroll;
  bool _ready = false;
  Timer? _scrollTimer;
  @override
  void initState() {
    super.initState();
    _note = widget.initial;
    _scroll = ScrollController();
    _scroll.addListener(_rememberScroll);
    unawaited(_loadPosition());
  }

  Future<void> _loadPosition() async {
    double position = 0;
    try {
      position =
          double.tryParse(
            await widget.controller.database.preference('scroll:${_note.id}') ??
                '',
          ) ??
          0;
      await widget.controller.opened(_note);
    } catch (_) {
      /* Cached content remains readable even if position saving fails. */
    }
    if (!mounted) {
      return;
    }
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          position.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
        );
      }
    });
  }

  void _rememberScroll() {
    if (!_ready || !_scroll.hasClients) {
      return;
    }
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 150), _savePosition);
  }

  void _savePosition() {
    if (!_scroll.hasClients) {
      return;
    }
    unawaited(
      widget.controller.database
          .setPreference('scroll:${_note.id}', _scroll.offset.toString())
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _savePosition();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            EditorScreen(controller: widget.controller, initial: _note),
      ),
    );
    try {
      final latest = await widget.controller.database.note(_note.id);
      if (mounted && latest == null) {
        Navigator.pop(context);
        return;
      }
      if (mounted && latest != null) {
        setState(() => _note = latest);
      }
    } catch (_) {
      if (mounted) {
        showFailure(context, 'متن تازه باز نشد؛ دوباره وارد یادداشت شوید.');
      }
    }
  }

  Future<void> _favorite() async {
    try {
      final saved = await widget.controller.save(
        _note.copyWith(favorite: !_note.favorite),
      );
      if (mounted) {
        setState(() => _note = saved);
      }
    } catch (_) {
      if (mounted) {
        showFailure(context);
      }
    }
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      'انتقال به حذف‌شده‌ها؟',
      'این یادداشت بعداً از تنظیمات قابل بازیابی است.',
      action: 'انتقال بده',
    )) {
      return;
    }
    try {
      await widget.controller.save(_note.copyWith(deleted: true));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        showFailure(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('خواندن یادداشت'),
        actions: [
          IconButton(
            tooltip: _note.favorite ? 'برداشتن نشان' : 'نشان کردن',
            onPressed: _favorite,
            icon: Icon(_note.favorite ? Icons.star : Icons.star_border),
          ),
          PopupMenuButton<String>(
            tooltip: 'گزینه‌های یادداشت',
            onSelected: (value) async {
              if (value == 'delete') {
                await _delete();
              }
              if (value == 'history' && context.mounted) {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryScreen(
                      controller: widget.controller,
                      note: _note,
                    ),
                  ),
                );
                try {
                  final latest = await widget.controller.database.note(
                    _note.id,
                  );
                  if (mounted && latest != null) {
                    setState(() => _note = latest);
                  }
                } catch (_) {
                  if (context.mounted) {
                    showFailure(context);
                  }
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'history', child: Text('نسخه‌های قبلی')),
              PopupMenuItem(
                value: 'delete',
                child: Text('انتقال به حذف‌شده‌ها'),
              ),
            ],
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.controller.categoryName(_note.categoryId),
                  style: const TextStyle(
                    fontSize: NotebookTypeScale.small,
                    color: NotebookColors.gold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _note.displayTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _note.bodyIsHtml
                        ? HtmlWidget(
                            readableHtml(
                              _note.body,
                              widget.controller.library.api.endpoint,
                            ),
                            textStyle: TextStyle(
                              fontSize: widget.controller.textSize,
                              height: 1.9,
                            ),
                            buildAsync: false,
                          )
                        : SelectableText(
                            _note.body.isEmpty
                                ? 'هنوز متنی نوشته نشده است.'
                                : _note.body,
                            style: TextStyle(
                              fontSize: widget.controller.textSize,
                              height: 1.9,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('اندازه متن'),
                    OutlinedButton(
                      onPressed: () => _size(-1),
                      child: const Text('کوچک‌تر'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _size(1),
                      child: const Text('بزرگ‌تر'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const SoftMessage(
                  title: 'این متن روی گوشی ذخیره است',
                  message: 'قطع اینترنت این صفحه را نمی‌بندد.',
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('ویرایش یادداشت'),
          ),
        ),
      ),
    ),
  );
  Future<void> _size(double change) async {
    try {
      await widget.controller.adjustTextSize(change.toInt());
    } catch (_) {
      if (mounted) {
        showFailure(context);
      }
    }
  }
}
