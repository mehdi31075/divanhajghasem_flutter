import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;
import '../application/notebook_controller.dart';
import '../domain/library.dart';
import 'widgets.dart';
import 'theme.dart';
import 'editor_screen.dart';
import '../data/post_api.dart';
import 'server_login_screen.dart';

// Preserve the original HTML in SQLite; adapt only its presentation so the
// old editor's fixed font sizes cannot override the reader's text-size setting.
String readableHtml(String source, Uri baseUrl) {
  final fragment = html.parseFragment(source);
  for (final element in fragment.querySelectorAll('*').toList()) {
    if (const [
      'script',
      'style',
      'iframe',
      'object',
      'embed',
      'link',
    ].contains(element.localName)) {
      element.remove();
      continue;
    }
    element.attributes.removeWhere((key, _) => key.toString().startsWith('on'));
    element.attributes.remove('size');
    element.attributes.remove('face');
    final styles = (element.attributes['style'] ?? '')
        .split(';')
        .where(
          (rule) => const [
            'text-align',
            'font-weight',
            'font-style',
            'text-decoration',
          ].contains(rule.split(':').first.trim().toLowerCase()),
        );
    element.attributes['style'] = styles.join(';');
    if (element.localName == 'img') {
      final raw = element.attributes['src'];
      final uri = raw == null ? null : Uri.tryParse(raw);
      final resolved = uri == null ? null : baseUrl.resolveUri(uri);
      if (resolved == null || !['http', 'https'].contains(resolved.scheme)) {
        element.remove();
      } else {
        element.attributes['src'] = resolved.toString();
      }
    }
  }
  return fragment.outerHtml;
}

class LibraryReaderScreen extends StatefulWidget {
  const LibraryReaderScreen({
    super.key,
    required this.controller,
    required this.article,
  });
  final NotebookController controller;
  // Immutable snapshot: a cache refresh never changes an open reading page.
  final LibraryArticle article;
  @override
  State<LibraryReaderScreen> createState() => _LibraryReaderScreenState();
}

class _LibraryReaderScreenState extends State<LibraryReaderScreen> {
  final _scroll = ScrollController();
  Timer? _timer;
  bool _ready = false;
  bool _working = false;
  String? _error;
  bool _pendingDelete = false;
  late final String _html;
  String get _positionKey =>
      'library-scroll:${widget.controller.library.api.endpoint}:${widget.article.id}';

  @override
  void initState() {
    super.initState();
    _html = readableHtml(
      widget.article.htmlBody,
      widget.controller.library.api.endpoint,
    );
    _scroll.addListener(() {
      if (!_ready) return;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 200), _savePosition);
    });
    unawaited(_restorePosition());
    unawaited(_loadPendingDelete());
  }

  Future<void> _edit() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final draft = await widget.controller.draftForArticle(widget.article);
      if (!mounted) return;
      var published = false;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EditorScreen(
            controller: widget.controller,
            initial: draft,
            onPublished: () => published = true,
          ),
        ),
      );
      if (published && mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'ویرایش مطلب باز نشد.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _loadPendingDelete() async {
    try {
      final pending = await widget.controller.posts.pendingDelete(
        widget.article.id,
      );
      if (mounted) setState(() => _pendingDelete = pending);
    } catch (_) {}
  }

  Future<void> _delete() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final pending = await widget.controller.posts.pendingDelete(
        widget.article.id,
      );
      if (!mounted) return;
      if (!pending) {
        if (!await confirm(
          context,
          'حذف مطلب از سرور؟',
          '«${plainHtml(widget.article.title)}» از سرور حذف می‌شود. سرور فعلی سطل زباله ندارد و این حذف قابل بازگردانی نیست.',
          action: 'حذف از سرور',
        )) {
          return;
        }
        if (!mounted ||
            !await ensureServerLogin(context, widget.controller.posts.api)) {
          return;
        }
      }
      await widget.controller.deletePost(widget.article);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حذف مطلب از سرور تأیید شد.')),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PostFailure
              ? error.message
              : 'حذف مطلب از سرور تأیید نشد.',
        );
      }
      await _loadPendingDelete();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restorePosition() async {
    double position = 0;
    try {
      position =
          double.tryParse(
            await widget.controller.database.preference(_positionKey) ?? '',
          ) ??
          0;
    } catch (_) {
      /* Reading does not depend on preferences being writable. */
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (position.isFinite) {
        _scroll.jumpTo(
          position.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
        );
      }
      _ready = true;
    });
    setState(() {});
  }

  void _savePosition() {
    if (!_ready || !_scroll.hasClients) return;
    unawaited(
      widget.controller.database
          .setPreference(_positionKey, _scroll.offset.toString())
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _savePosition();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _size(double delta) async {
    try {
      await widget.controller.setTextSize(widget.controller.textSize + delta);
    } catch (_) {
      if (mounted) showFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(title: const Text('مطالعهٔ دیوان')),
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                plainHtml(widget.article.title),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (widget.article.subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(plainHtml(widget.article.subtitle)),
                ),
              const SizedBox(height: 16),
              Text('تاریخ ایجاد: ${_articleDate(widget.article.createdAt)}'),
              Text('آخرین ویرایش: ${_articleDate(widget.article.updatedAt)}'),
              const SizedBox(height: 24),
              SelectionArea(
                child: HtmlWidget(
                  _html,
                  baseUrl: widget.controller.library.api.endpoint,
                  buildAsync: false,
                  textStyle: TextStyle(
                    fontFamily: 'Vazirmatn',
                    fontSize: widget.controller.textSize,
                    height: 1.9,
                  ),
                  onErrorBuilder: (_, _, _) =>
                      const Text('تصویر در دسترس نیست.'),
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                SoftMessage(
                  title: 'درخواست تکمیل نشد',
                  message: _error!,
                  isError: true,
                ),
              if (widget.controller.isAdmin)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      key: const Key('edit-post'),
                      onPressed: _working ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('ویرایش مطلب'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('delete-post'),
                      onPressed: _working ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        _pendingDelete ? 'بررسی نتیجهٔ حذف' : 'حذف از سرور',
                      ),
                    ),
                  ],
                ),
              if (_working)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('در حال بررسی...'),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 64),
                    ),
                    onPressed: widget.controller.textSize <= 20
                        ? null
                        : () => _size(-2),
                    child: const Text('کوچک‌تر'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.controller.textSize >= 32
                        ? null
                        : () => _size(2),
                    child: const Text('بزرگ‌تر'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _articleDate(DateTime? value) {
  if (value == null) return 'ثبت نشده';
  final date = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${faDigits('${date.year}/${two(date.month)}/${two(date.day)} · ${two(date.hour)}:${two(date.minute)}')} (میلادی)';
}
