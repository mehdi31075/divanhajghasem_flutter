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
      await widget.api.login(_username.text.trim(), _password.text);
      _password.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is PostFailure
              ? error.message
              : 'ارتباط با سرور برقرار نشد. دوباره تلاش کنید.';
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
    appBar: AppBar(title: const Text('ورود به حساب')),
    body: PageBody(
      children: [
        const Text('برای ایجاد، ویرایش و حذف مطالب وارد حساب مدیر دیوان انصارالحسین(ع) شوید.'),
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
