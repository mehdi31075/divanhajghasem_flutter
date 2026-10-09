import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:hajqasem_app/domain/library.dart';
import 'package:hajqasem_app/ui/library_reader_screen.dart';

void main() {
  test('reader keeps safe inline images and uploaded videos playable', () {
    final output = html.parseFragment(readableHtml(
      '<p>پیش از رسانه</p><figure><img src="upload/news-media/pic.png"></figure>'
      '<figure class="media"><video controls playsinline><source src="/upload/news-media/clip.mp4" type="video/mp4"></video></figure>'
      '<video src="javascript:alert(1)"></video>',
      Uri.parse('https://divanhajghasem.ir/api.php'),
    ));
    expect(output.querySelector('img')!.attributes['src'],
        'https://divanhajghasem.ir/upload/news-media/pic.png');
    expect(output.querySelector('video')!.attributes.containsKey('controls'), isTrue);
    expect(output.querySelector('video source')!.attributes['src'],
        'https://divanhajghasem.ir/upload/news-media/clip.mp4');
    expect(output.querySelectorAll('video'), hasLength(1));
  });

  test('reader canonicalizes HTTP and index.php media URLs against default API endpoint', () {
    final defaultEndpoint = Uri.parse('http://divanhajghasem.ir/index.php/api.php');
    final output = html.parseFragment(readableHtml(
      '<figure><img src="upload/news-media/relative.png"></figure>'
      '<figure><img src="/index.php/upload/news-media/corrupted.png"></figure>'
      '<figure><img src="http://divanhajghasem.ir/upload/news-media/http_pic.png"></figure>'
      '<figure><img src="http://localhost:8000/upload/news-media/dev_pic.png"></figure>',
      defaultEndpoint,
    ));
    final images = output.querySelectorAll('img');
    expect(images[0].attributes['src'],
        'http://divanhajghasem.ir/upload/news-media/relative.png');
    expect(images[1].attributes['src'],
        'http://divanhajghasem.ir/upload/news-media/corrupted.png');
    expect(images[2].attributes['src'],
        'http://divanhajghasem.ir/upload/news-media/http_pic.png');
    expect(images[3].attributes['src'],
        'http://divanhajghasem.ir/upload/news-media/dev_pic.png');
  });

  test(
    'article timestamps survive the cache format without invented dates',
    () {
      final article = LibraryArticle.fromJson({
        'nid': '7',
        'cat_id': '61',
        'news_heading': 'عنوان',
        'news_date': 'به قلم نویسنده',
        'news_description': '<p>متن</p>',
        'created_at': '2026-10-01T10:00:00Z',
        'updated_at': '2026-10-06T11:00:00Z',
      });
      final restored = LibraryArticle.fromJson(article.toJson());
      expect(restored.createdAt, DateTime.utc(2026, 10, 1, 10));
      expect(restored.updatedAt, DateTime.utc(2026, 10, 6, 11));
      expect(restored.subtitle, 'به قلم نویسنده');
      final legacy = {...article.toJson()}
        ..remove('created_at')
        ..remove('updated_at');
      expect(LibraryArticle.fromJson(legacy).createdAt, isNull);
      expect(LibraryArticle.fromJson(legacy).updatedAt, isNull);
    },
  );
}
