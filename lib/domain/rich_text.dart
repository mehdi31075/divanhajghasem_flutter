import 'dart:convert';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:html/parser.dart' as html;
import 'note.dart';

quill.Document documentForNote(Note note, {Uri? baseUrl}) {
  if (note.richTextDelta != null) {
    return quill.Document.fromJson(jsonDecode(note.richTextDelta!) as List);
  }
  if (note.bodyIsHtml && note.body.isNotEmpty) {
    final fragment = html.parseFragment(note.body);
    for (final element in fragment.querySelectorAll('script,style')) {
      element.remove();
    }
    final origin =
        baseUrl ??
        (note.serverSource == null ? null : Uri.tryParse(note.serverSource!));
    if (origin != null) {
      for (final element in fragment.querySelectorAll('img[src],a[href]')) {
        final attribute = element.localName == 'img' ? 'src' : 'href';
        final value = Uri.tryParse(element.attributes[attribute]!);
        if (value != null && !value.hasScheme) {
          element.attributes[attribute] = origin.resolveUri(value).toString();
        }
      }
    }
    final delta = HtmlToDelta().convert(
      fragment.outerHtml,
      transformTableAsEmbed: false,
    );
    return quill.Document.fromJson(delta.toJson());
  }
  return quill.Document.fromJson([
    {'insert': '${note.body}\n'},
  ]);
}

String documentHtml(quill.Document document) =>
    document.toPlainText().trim().isEmpty
    ? ''
    : QuillDeltaToHtmlConverter(
        document.toDelta().toJson(),
        ConverterOptions.forEmail(),
      ).convert();
