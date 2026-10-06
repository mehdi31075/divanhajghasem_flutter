import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

class RichTextEditor extends StatefulWidget {
  const RichTextEditor({
    super.key,
    required this.controller,
    required this.baseUrl,
    required this.fontSize,
    required this.enabled,
  });
  final quill.QuillController controller;
  final Uri baseUrl;
  final double fontSize;
  final bool enabled;

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.controller.readOnly = !widget.enabled;
    return Localizations.override(
      context: context,
      delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IgnorePointer(
            ignoring: !widget.enabled,
            child: quill.QuillSimpleToolbar(
              controller: widget.controller,
              config: const quill.QuillSimpleToolbarConfig(
                showFontFamily: false,
                showFontSize: false,
                showStrikeThrough: false,
                showInlineCode: false,
                showBackgroundColorButton: false,
                showAlignmentButtons: true,
                showListCheck: false,
                showCodeBlock: false,
                showQuote: false,
                showIndent: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: quill.QuillEditor.basic(
              key: const Key('note-body'),
              controller: widget.controller,
              focusNode: _focus,
              scrollController: _scroll,
              config: quill.QuillEditorConfig(
                scrollable: false,
                minHeight: 240,
                padding: const EdgeInsets.all(16),
                placeholder: 'متن نوشته را اینجا بنویسید...',
                customStyles: quill.DefaultStyles(
                  paragraph: quill.DefaultTextBlockStyle(
                    TextStyle(
                      fontFamily: 'Vazirmatn',
                      fontSize: widget.fontSize,
                      height: 1.9,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    const quill.HorizontalSpacing(0, 0),
                    const quill.VerticalSpacing(0, 0),
                    const quill.VerticalSpacing(0, 0),
                    null,
                  ),
                ),
                embedBuilders: [_ImageEmbedBuilder(widget.baseUrl)],
                unknownEmbedBuilder: const _UnknownEmbedBuilder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageEmbedBuilder extends quill.EmbedBuilder {
  const _ImageEmbedBuilder(this.baseUrl);
  final Uri baseUrl;
  @override
  String get key => 'image';
  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final uri = baseUrl.resolve(embedContext.node.value.data.toString());
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return const Text('تصویر در دسترس نیست.');
    }
    return Image.network(
      uri.toString(),
      fit: BoxFit.contain,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (_, _, _) => const Text('تصویر در دسترس نیست.'),
    );
  }
}

class _UnknownEmbedBuilder extends quill.EmbedBuilder {
  const _UnknownEmbedBuilder();
  @override
  String get key => 'unknown';
  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) =>
      const Text('محتوای پیوست‌شده');
}
