import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../domain/rich_text.dart';
import 'rich_text_editor.dart';
import '../application/notebook_controller.dart';
import '../data/post_api.dart';
import 'server_login_screen.dart';
import '../domain/note.dart';
import 'library_reader_screen.dart' show readableHtml;
import 'theme.dart';
import 'widgets.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.controller,
    required this.initial,
    this.onPublished,
  });
  final NotebookController controller;
  final Note initial;
  final VoidCallback? onPublished;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late Note _draft;
  late TextEditingController _title;
  late quill.QuillController _rich;
  late String _lastRichDelta;
  late bool _richActive;
  bool _richLoadFailed = false;
  late TextEditingController _subtitle;
  Future<bool> _lastWrite = Future.value(true);
  Future<void>? _baseWrite;
  int _generation = 0;
  final String _editSession = newId();
  bool _saving = false;
  bool _failed = false;
  bool _finishing = false;
  bool _allowPop = false;
  bool _changed = false;
  bool _loadingCategories = true;
  bool _categoriesFailed = false;
  bool _publishing = false;
  String? _postError;
  bool _pendingPost = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft = widget.initial;
    _title = TextEditingController(text: _draft.title);
    try {
      _rich = quill.QuillController(
        document: documentForNote(
          _draft,
          baseUrl: widget.controller.library.api.endpoint,
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      _richActive = !_draft.bodyIsHtml || _draft.richTextDelta != null;
    } catch (_) {
      _rich = quill.QuillController.basic();
      _richActive = false;
      _richLoadFailed = true;
    }
    _lastRichDelta = jsonEncode(_rich.document.toDelta().toJson());
    _rich.addListener(_richEdited);
    _subtitle = TextEditingController(text: _draft.subtitle);
    unawaited(_loadCategories());
    unawaited(_loadPending());
  }

  Future<void> _loadPending() async {
    try {
      final pending = await widget.controller.posts.pendingDraft(_draft.id);
      if (mounted) setState(() => _pendingPost = pending);
    } catch (_) {
      /* The service checks again before any request. */
    }
  }

  Future<void> _publish() async {
    if (_publishing || _finishing) return;
    setState(() {
      _publishing = true;
      _postError = null;
    });
    try {
      if (!await _lastWrite || _failed) {
        throw const PostFailure('ابتدا پیش‌نویس را دوباره ذخیره کنید.');
      }
      if (!await _persist() || !mounted) return;
      final pending = await widget.controller.posts.pendingDraft(_draft.id);
      if (!mounted) return;
      if (!pending &&
          (_draft.categoryId == null ||
              [
                _draft.title,
                _draft.subtitle,
                _draft.body,
              ].any((text) => text.trim().isEmpty))) {
        throw const PostFailure('عنوان، عنوان فرعی، دسته و متن را کامل کنید.');
      }
      if (!pending &&
          !await ensureServerLogin(context, widget.controller.posts.api)) {
        return;
      }
      if (!mounted) return;
      final remaining = await widget.controller.publish(_draft);
      if (!mounted) return;
      if (remaining != null) {
        setState(() {
          _draft = remaining;
          _pendingPost = false;
          _postError =
              'نسخهٔ ارسال‌شده روی سرور ثبت شد. تغییرات تازه‌تر هنوز پیش‌نویس‌اند؛ برای ثبت آن‌ها دوباره ذخیره کنید.';
        });
        return;
      }
      widget.onPublished?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('مطلب روی سرور ذخیره شد.')));
      setState(() {
        _allowPop = true;
        _finishing = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _postError = error is PostFailure
              ? error.message
              : 'ذخیره روی سرور تأیید نشد؛ پیش‌نویس محفوظ است.',
        );
      }
      await _loadPending();
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _editBody() async {
    if (_richLoadFailed) {
      showFailure(
        context,
        'متن در ویرایشگر باز نشد. متن اصلی محفوظ است؛ عنوان و دسته را می‌توانید تغییر دهید.',
      );
      return;
    }
    if (!await confirm(
      context,
      'ویرایش متن مطلب',
      'متن در ویرایشگر قالب‌دار باز می‌شود. قالب‌های پیچیدهٔ HTML ممکن است هنگام تغییر متن به قالب‌های پشتیبانی‌شده تبدیل شوند. نسخهٔ قبلی محفوظ می‌ماند.',
      action: 'باز کردن ویرایشگر',
    )) {
      return;
    }
    if (!mounted) return;
    if (!await _persist() || !mounted) return;
    setState(() => _richActive = true);
  }

  void _richEdited() {
    if (!_richActive || _finishing || _publishing) return;
    final delta = jsonEncode(_rich.document.toDelta().toJson());
    if (delta == _lastRichDelta) return;
    _lastRichDelta = delta;
    _draft = _draft.copyWith(
      body: documentHtml(_rich.document),
      bodyIsHtml: true,
      richTextDelta: delta,
    );
    _edited();
  }

  Future<void> _loadCategories({bool refresh = false}) async {
    setState(() {
      _loadingCategories = true;
      _categoriesFailed = false;
    });
    try {
      if (refresh || await widget.controller.cachedCategories() == null) {
        await widget.controller.refreshCategories();
      }
    } catch (_) {
      if (mounted) setState(() => _categoriesFailed = true);
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  void _edited() {
    _draft = _draft.copyWith(title: _title.text, subtitle: _subtitle.text);
    _changed = true;
    _lastWrite = _persist();
  }

  Future<bool> _persist() async {
    final generation = ++_generation;
    final snapshot = _draft;
    if (mounted) {
      setState(() {
        _saving = true;
        _failed = false;
      });
    }
    try {
      if (widget.initial.original != null) {
        _baseWrite ??= (() async {
          if (await widget.controller.database.note(widget.initial.id) ==
              null) {
            await widget.controller.save(widget.initial);
          }
        })();
        try {
          await _baseWrite;
        } catch (_) {
          _baseWrite = null;
          rethrow;
        }
      }
      final saved = await widget.controller.save(
        snapshot,
        editSession: _editSession,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _draft = saved;
          _saving = false;
          _failed = false;
        });
      }
      return true;
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return false;
    }
  }

  Future<void> _finish() async {
    if (_finishing || _publishing) {
      return;
    }
    setState(() => _finishing = true);
    final saved = await _lastWrite;
    if (!mounted) {
      return;
    }
    if (!saved || _failed) {
      setState(() => _finishing = false);
      showFailure(
        context,
        'نوشته هنوز ذخیره نشده. «دوباره ذخیره کن» را بزنید.',
      );
      return;
    }
    if (_changed) {
      try {
        await widget.controller.opened(_draft);
      } catch (_) {
        /* Reading position is optional; the note itself is durable. */
      }
      if (!mounted) {
        return;
      }
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _changed &&
        !_finishing &&
        !_publishing) {
      _lastWrite = _persist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.dispose();
    _rich.removeListener(_richEdited);
    _rich.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        unawaited(_finish());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial.original != null ? 'ویرایش مطلب' : 'مطلب تازه',
        ),
        leading: BackButton(onPressed: _finish),
      ),
      body: PageBody(
        children: [
          SoftMessage(
            title: _failed
                ? 'ذخیره نشد'
                : _saving
                ? 'در حال ذخیره روی گوشی...'
                : _changed
                ? 'پیش‌نویس روی گوشی ذخیره شد'
                : 'با خیال راحت بنویسید',
            message: _failed
                ? 'متن در این صفحه باقی است. دوباره ذخیره کنید.'
                : 'پیش‌نویس خودکار ذخیره می‌شود. برای ثبت مطلب روی سرور، «ذخیره روی سرور» را بزنید.',
            icon: _failed
                ? Icons.error_outline
                : _saving
                ? Icons.hourglass_top
                : Icons.check_circle_outline,
            isError: _failed,
          ),
          if (_failed)
            FilledButton(
              onPressed: () {
                _lastWrite = _persist();
              },
              child: const Text('دوباره ذخیره کن'),
            ),
          TextField(
            key: const Key('note-title'),
            controller: _title,
            enabled: !_finishing && !_publishing,
            onChanged: (_) => _edited(),
            decoration: const InputDecoration(labelText: 'عنوان یادداشت'),
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 22),
          ),
          TextField(
            key: const Key('post-subtitle'),
            controller: _subtitle,
            enabled: !_finishing && !_publishing,
            onChanged: (_) => _edited(),
            decoration: const InputDecoration(labelText: 'عنوان فرعی'),
            textInputAction: TextInputAction.next,
          ),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => DropdownButtonFormField<String>(
              key: ValueKey(_draft.categoryId),
              initialValue: _draft.categoryId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'دسته‌بندی'),
              items: [
                const DropdownMenuItem(value: '', child: Text('بدون دسته')),
                if (_draft.categoryId != null &&
                    !widget.controller.categories.any(
                      (category) => category.id == _draft.categoryId,
                    ))
                  DropdownMenuItem(
                    value: _draft.categoryId,
                    enabled: false,
                    child: const Text('دستهٔ قبلی (در فهرست فعلی نیست)'),
                  ),
                for (final category in widget.controller.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: _finishing || _publishing
                  ? null
                  : (id) {
                      _draft = _draft.copyWith(
                        categoryId: id,
                        clearCategory: id == null || id.isEmpty,
                      );
                      _changed = true;
                      _lastWrite = _persist();
                    },
            ),
          ),
          if (_loadingCategories)
            const Text('در حال دریافت دسته‌بندی‌ها...')
          else if (_categoriesFailed)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'دسته‌بندی‌ها دریافت نشد. می‌توانید به نوشتن ادامه دهید.',
                ),
                OutlinedButton(
                  onPressed: () => _loadCategories(refresh: true),
                  child: const Text('دریافت دوبارهٔ دسته‌بندی‌ها'),
                ),
              ],
            )
          else if (widget.controller.categories.isEmpty)
            const Text('هنوز دسته‌بندی‌ای دریافت نشده است.'),
          if (!_richActive) ...[
            HtmlWidget(
              readableHtml(_draft.body, widget.controller.library.api.endpoint),
              textStyle: TextStyle(
                fontSize: widget.controller.textSize,
                height: 1.9,
              ),
              buildAsync: false,
            ),
            OutlinedButton.icon(
              onPressed: _publishing || _finishing ? null : _editBody,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('ویرایش متن مطلب'),
            ),
          ] else
            RichTextEditor(
              controller: _rich,
              baseUrl: widget.controller.library.api.endpoint,
              fontSize: widget.controller.textSize,
              enabled: !_finishing && !_publishing,
            ),
          if (_postError != null)
            SoftMessage(
              title: 'ذخیره تکمیل نشد',
              message: _postError!,
              isError: true,
            ),
          OutlinedButton(
            onPressed: _finishing || _publishing ? null : _finish,
            child: const Text('بستن و نگه‌داشتن پیش‌نویس'),
          ),
          const Text(
            'نوشته تا تأیید سرور به‌صورت پیش‌نویس روی دستگاه نگه داشته می‌شود.',
            style: TextStyle(fontSize: 16, color: NotebookColors.muted),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('publish-post'),
            onPressed: _finishing || _publishing ? null : _publish,
            child: Text(
              _publishing
                  ? 'در حال بررسی...'
                  : _pendingPost
                  ? 'بررسی نتیجهٔ ارسال'
                  : 'ذخیره روی سرور',
            ),
          ),
        ),
      ),
    ),
  );
}
