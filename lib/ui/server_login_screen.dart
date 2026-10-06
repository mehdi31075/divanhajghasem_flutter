import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/post_api.dart';
import 'widgets.dart';

Future<bool> ensureServerLogin(BuildContext context, PostApi api) async {
  if (api.canManage) return true;
  return await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ServerLoginScreen(api: api)),
      ) ??
      false;
}

class ServerLoginScreen extends StatefulWidget {
  const ServerLoginScreen({super.key, required this.api});
  final PostApi api;
  @override
  State<ServerLoginScreen> createState() => _ServerLoginScreenState();
}

class _ServerLoginScreenState extends State<ServerLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (kDebugMode) {
        if (!widget.api.unlockLocalPreview(
          _username.text.trim(),
          _password.text,
        )) {
          throw const InvalidCredentials();
        }
      } else {
        await widget.api.login(_username.text.trim(), _password.text);
      }
      _password.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          if (error is InvalidCredentials) {
            _error = error.message;
          } else if (kIsWeb && Uri.base.origin != widget.api.endpoint.origin) {
            _error =
                'ورود از پیش‌نمایش وب به نشست سایت دسترسی ندارد. '
                'سرور باید CORS و کوکی ورود را برای وب تنظیم کند؛ '
                'ورود در نسخهٔ Android این محدودیت مرورگر را ندارد.';
          } else if (error is PostFailure) {
            _error = error.message;
          } else {
            _error = 'ارتباط با سرور برقرار نشد. دوباره تلاش کنید.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(kDebugMode ? 'ورود آزمایشی' : 'ورود به حساب')),
    body: PageBody(
      children: [
        Text(
          kDebugMode
              ? 'این ورود فقط ابزارهای مدیریت را برای آزمایش باز می‌کند؛ ذخیره روی سایت همچنان به نشست واقعی سرور نیاز دارد.'
              : 'برای ذخیره و حذف مطالب روی سرور وارد حساب دیوان شوید.',
        ),
        TextField(
          key: const Key('server-username'),
          controller: _username,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'نام کاربری'),
        ),
        TextField(
          key: const Key('server-password'),
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'رمز عبور'),
        ),
        if (_error != null)
          SoftMessage(title: 'ورود انجام نشد', message: _error!, isError: true),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: Text(_busy ? 'در حال ورود...' : 'ورود'),
        ),
      ],
    ),
  );
}
