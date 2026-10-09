import 'dart:async';
import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import '../domain/note.dart';
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
  late TextEditingController _body;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft = widget.initial;
    _title = TextEditingController(text: _draft.title);
    _title.addListener(_titleEdited);
    _subtitle = TextEditingController(text: _draft.subtitle);
    _subtitle.addListener(_subtitleEdited);
    _body = TextEditingController(text: _draft.body);
    _body.addListener(_bodyEdited);
    unawaited(_loadCategories());
  }

  void _titleEdited() {
    if (_finishing || _title.text == _draft.title) return;
    _draft = _draft.copyWith(title: _title.text);
    _edited();
  }

  void _subtitleEdited() {
    if (_finishing || _subtitle.text == _draft.subtitle) return;
    _draft = _draft.copyWith(subtitle: _subtitle.text);
    _edited();
  }

  void _bodyEdited() {
    if (_finishing || _body.text == _draft.body) return;
    _draft = _draft.copyWith(body: _body.text, bodyIsHtml: false);
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
    if (_finishing) {
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
    if (state == AppLifecycleState.paused && _changed && !_finishing) {
      _lastWrite = _persist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.dispose();
    _subtitle.dispose();
    _body.dispose();
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
            enabled: !_finishing,
            onChanged: (_) => _edited(),
            decoration: const InputDecoration(labelText: 'عنوان یادداشت'),
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: NotebookTypeScale.body),
          ),
          TextField(
            key: const Key('post-subtitle'),
            controller: _subtitle,
            enabled: !_finishing,
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
              onChanged: _finishing
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
          TextField(
            key: const Key('note-body'),
            controller: _body,
            enabled: !_finishing,
            maxLines: null,
            minLines: 6,
            decoration: const InputDecoration(
              labelText: 'متن مطلب',
              alignLabelWithHint: true,
            ),
            style: TextStyle(
              fontSize: widget.controller.textSize,
              height: 1.9,
            ),
          ),
          OutlinedButton(
            onPressed: _finishing ? null : _finish,
            child: const Text('بستن و نگه‌داشتن پیش‌نویس'),
          ),
          const Text(
            'نوشته تا تأیید سرور به‌صورت پیش‌نویس روی دستگاه نگه داشته می‌شود.',
            style: TextStyle(
              fontSize: NotebookTypeScale.small,
              color: NotebookColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
