import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/notebook_controller.dart';
import '../domain/content_page.dart';
import 'library_reader_screen.dart' show readableHtml;
import 'widgets.dart';

class ContentPageScreen extends StatefulWidget {
  const ContentPageScreen({
    super.key,
    required this.controller,
    required this.slug,
    required this.label,
  });
  final NotebookController controller;
  final String slug;
  final String label;

  @override
  State<ContentPageScreen> createState() => _ContentPageScreenState();
}

class _ContentPageScreenState extends State<ContentPageScreen> {
  ContentPage? _page;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final library = widget.controller.library;
    try {
      final cached = await library.cachedPages();
      if (!mounted) return;
      if (cached != null) {
        setState(
          () => _page ??= cached.firstWhere((p) => p.slug == widget.slug),
        );
      }
      final fresh = await library.refreshPages();
      if (!mounted) return;
      // Refresh the cache, but never replace text that is already being read.
      setState(() => _page ??= fresh.firstWhere((p) => p.slug == widget.slug));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _page == null
              ? 'متن بارگذاری نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.'
              : 'به‌روزرسانی انجام نشد؛ آخرین متن دریافت‌شده را می‌خوانید.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _openLink(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !const ['http', 'https', 'mailto', 'tel'].contains(uri.scheme)) {
      return false;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      /* Keep the reader open when there is no suitable app. */
    }
    if (mounted) showFailure(context, 'باز کردن پیوند انجام نشد.');
    return false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(_page?.title ?? widget.label)),
      body: PageBody(
        children: [
          if (_page == null && _loading)
            const Center(child: CircularProgressIndicator()),
          if (_error != null) ...[
            SoftMessage(
              title: _page == null ? 'دریافت نشد' : 'متن ذخیره‌شده',
              message: _error!,
              isError: _page == null,
              icon: Icons.wifi_off,
            ),
            if (_page == null)
              FilledButton(
                onPressed: _loading ? null : _load,
                child: const Text('تلاش دوباره'),
              ),
          ],
          if (_page != null)
            HtmlWidget(
              readableHtml(
                _page!.htmlBody,
                widget.controller.library.api.endpoint,
              ),
              textStyle: TextStyle(
                fontSize: widget.controller.textSize,
                height: 1.9,
              ),
              onTapUrl: _openLink,
            ),
        ],
      ),
    ),
  );
}
