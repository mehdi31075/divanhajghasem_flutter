import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../application/notebook_controller.dart';
import '../domain/library.dart';
import 'library_reader_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final NotebookController controller;
  final bool embedded;

  @override
  Widget build(BuildContext context) => _CachedLibraryPage<LibraryCategory>(
    title: 'دسته‌بندی‌های دیوان',
    embedded: embedded,
    grid: true,
    cached: controller.cachedCategories,
    refresh: controller.refreshCategories,
    searchText: (category) => plainHtml('${category.name} ${category.author}'),
    emptyMessage: 'هنوز دسته‌ای در دیوان نیست.',
    itemBuilder: (context, category) => _CategoryCard(
      category: category,
      image: controller.library.api.categoryImage(category),
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              LibraryArticlesScreen(controller: controller, category: category),
        ),
      ),
    ),
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.image,
    required this.onTap,
  });
  final LibraryCategory category;
  final Uri? image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = plainHtml(category.name);
    return Semantics(
      button: true,
      child: Tooltip(
        message: name,
        excludeFromSemantics: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('category-${category.id}'),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(
                    color: NotebookColors.soft,
                    child: image == null
                        ? const _CategoryImagePlaceholder()
                        : Image.network(
                            image.toString(),
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.prefer,
                            // Category artwork can contain lettering; show it whole.
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : const Center(
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                            errorBuilder: (_, _, _) =>
                                const _CategoryImagePlaceholder(),
                          ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: NotebookColors.ink,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plainHtml(category.author),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  color: NotebookColors.muted,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward,
                              size: 24,
                              color: NotebookColors.teal,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryImagePlaceholder extends StatelessWidget {
  const _CategoryImagePlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(
      Icons.auto_stories_outlined,
      size: 48,
      color: NotebookColors.teal,
    ),
  );
}

class LibraryArticlesScreen extends StatelessWidget {
  const LibraryArticlesScreen({
    super.key,
    required this.controller,
    required this.category,
  });
  final NotebookController controller;
  final LibraryCategory category;

  @override
  Widget build(BuildContext context) => _CachedLibraryPage<LibraryArticle>(
    title: plainHtml(category.name),
    changes: controller.library,
    cached: () => controller.library.cachedArticles(category.id),
    refresh: () => controller.library.refreshArticles(category.id),
    searchText: (article) => article.searchableText,
    emptyMessage: 'این دسته هنوز مطلبی ندارد.',
    itemBuilder: (context, article) => ActionCard(
      title: plainHtml(article.title),
      subtitle: article.subtitle.isEmpty ? null : plainHtml(article.subtitle),
      icon: Icons.menu_book_outlined,
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              LibraryReaderScreen(controller: controller, article: article),
        ),
      ),
    ),
  );
}

class _CachedLibraryPage<T> extends StatefulWidget {
  const _CachedLibraryPage({
    required this.title,
    required this.cached,
    required this.refresh,
    required this.searchText,
    required this.itemBuilder,
    required this.emptyMessage,
    this.embedded = false,
    this.grid = false,
    this.changes,
    this.header,
  });
  final String title;
  final Future<List<T>?> Function() cached;
  final Future<List<T>> Function() refresh;
  final String Function(T) searchText;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyMessage;
  final bool embedded;
  final bool grid;
  final Listenable? changes;
  final Widget? header;
  @override
  State<_CachedLibraryPage<T>> createState() => _CachedLibraryPageState<T>();
}

class _CachedLibraryPageState<T> extends State<_CachedLibraryPage<T>> {
  List<T>? _items;
  bool _busy = true;
  bool _failed = false;
  Object? _failure;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    widget.changes?.addListener(_reloadCache);
  }

  void _reloadCache() {
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_reloadCache);
    super.dispose();
  }

  Future<void> _load() async {
    List<T>? cached;
    try {
      cached = await widget.cached();
    } catch (_) {
      /* Try a fresh fetch if the cached snapshot cannot be read. */
    }
    if (!mounted) return;
    setState(() {
      _items = cached;
      _busy = false;
    });
    // Show the last cached snapshot immediately, then fetch current API data.
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _failure = null;
    });
    try {
      final items = await widget.refresh();
      if (mounted) {
        setState(() {
          _items = items;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _failure = error;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _normalize(String s) =>
      s.replaceAll('ي', 'ی').replaceAll('ك', 'ک').toLowerCase();

  String get _failureMessage {
    final reason = _failure is TimeoutException
        ? 'پاسخ API بیش از حد طول کشید. دوباره تلاش کنید.'
        : _failure is FormatException
        ? 'پاسخ API قابل خواندن نیست. دوباره تلاش کنید.'
        : kIsWeb
        ? 'ارتباط با API برقرار نشد. پیش‌نمایش را در Chrome بازشده با تنظیمات توسعه امتحان کنید؛ مرورگر داخلی ممکن است درخواست را به‌دلیل CORS مسدود کند.'
        : 'ارتباط با API برقرار نشد. دوباره تلاش کنید.';
    return _items != null
        ? '$reason مطالب آخرین بازدید همچنان در دسترس‌اند.'
        : reason;
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _items
            ?.where(
              (item) => _normalize(
                widget.searchText(item),
              ).contains(_normalize(_query)),
            )
            .toList() ??
        <T>[];
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: CustomScrollView(
          key: PageStorageKey(widget.title),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.header != null) ...[
                      widget.header!,
                      const SizedBox(height: 16),
                    ],
                    if (widget.grid) ...[
                      const Text('برای دیدن مطالب، یک دسته را انتخاب کنید.'),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      decoration: InputDecoration(
                        hintText: widget.grid
                            ? 'جستجو در دسته‌بندی‌ها...'
                            : 'جستجو...',
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 16),
                    if (_failed)
                      SoftMessage(
                        title: 'بارگذاری انجام نشد',
                        isError: true,
                        message: _failureMessage,
                      ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 64),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _busy ? null : _refresh,
                        icon: Icon(_busy ? Icons.hourglass_top : Icons.refresh),
                        label: Text(
                          _busy
                              ? 'در حال به‌روزرسانی...'
                              : _failed
                              ? 'دوباره تلاش کن'
                              : 'به‌روزرسانی',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!_busy && !_failed && visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _query.isEmpty
                              ? widget.emptyMessage
                              : widget.grid
                              ? 'دسته‌ای پیدا نشد.'
                              : 'مطلبی پیدا نشد.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.grid)
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final scaler = MediaQuery.textScalerOf(context);
                  final minWidth = 156 * (scaler.scale(20) / 20);
                  final available = constraints.crossAxisExtent - 32;
                  final columns = ((available + 16) / (minWidth + 16))
                      .floor()
                      .clamp(1, 4);
                  final width = (available - 16 * (columns - 1)) / columns;
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent:
                            width * 3 / 4 +
                            scaler.scale(20) * 3 +
                            scaler.scale(16) * 1.5 +
                            40,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          widget.itemBuilder(context, visible[index]),
                    ),
                  );
                },
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: widget.itemBuilder(context, visible[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: content,
    );
  }
}
