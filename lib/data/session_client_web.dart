import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client sessionClient(Uri origin) =>
    BrowserClient()..withCredentials = true;
