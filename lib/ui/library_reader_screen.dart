import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:video_player/video_player.dart';
import 'package:html/parser.dart' as html;
import '../application/notebook_controller.dart';
import '../domain/library.dart';
import 'widgets.dart';
import 'theme.dart';

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
    if (element.localName == 'img' ||
        element.localName == 'video' ||
        element.localName == 'source') {
      final raw = element.attributes['src'];
      if (element.localName == 'video' &&
          raw == null &&
          element.querySelector('source[src]') != null) {
        continue;
      }
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
  late int _viewCount;
  late final String _html;
  String get _positionKey =>
      'library-scroll:${widget.controller.library.api.endpoint}:${widget.article.id}';

  @override
  void initState() {
    super.initState();
    _viewCount = widget.article.viewCount;
    unawaited(
      widget.controller.library
          .recordArticleView(widget.article)
          .then((count) {
            if (mounted) setState(() => _viewCount = count);
          })
          .catchError((Object _) {}),
    );
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
      await widget.controller.adjustTextSize(delta.toInt());
    } catch (_) {
      if (mounted) showFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: true,
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
              const SizedBox(height: 6),
              Text(
                'بازدید: $_viewCount',
                style: const TextStyle(fontSize: NotebookTypeScale.small),
              ),
              const SizedBox(height: 24),
              SelectionArea(
                child: HtmlWidget(
                  _html,
                  baseUrl: widget.controller.library.api.endpoint,
                  factoryBuilder: () => _DivanWidgetFactory(),
                  customWidgetBuilder: (element) {
                    if (element.localName != 'video') return null;
                    final src =
                        element.attributes['src'] ??
                        element.querySelector('source')?.attributes['src'];
                    final uri = src == null ? null : Uri.tryParse(src);
                    if (uri == null ||
                        !['http', 'https'].contains(uri.scheme)) {
                      return null;
                    }
                    return _InlineVideoPlayer(key: ValueKey(src), url: uri);
                  },
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
                    onPressed: widget.controller.textSize >= 28
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

class _DivanWidgetFactory extends WidgetFactory {}

class _InlineVideoPlayer extends StatefulWidget {
  const _InlineVideoPlayer({super.key, required this.url});
  final Uri url;

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(widget.url);
    _controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object _) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          if (value.hasError) {
            return const AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(
                child: Text(
                  'این ویدیو در دسترس نیست.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );
          }
          if (!value.isInitialized) {
            return const AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return AspectRatio(
            aspectRatio: value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller),
                IconButton.filledTonal(
                  tooltip: value.isPlaying ? 'مکث ویدیو' : 'پخش ویدیو',
                  iconSize: 36,
                  onPressed: () => value.isPlaying
                      ? _controller.pause()
                      : _controller.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ],
            ),
          );
        },
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
