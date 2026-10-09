import 'package:flutter/material.dart';

import '../application/notebook_controller.dart';

enum _LoginStep { mobile, otp, name }

class AccountLoginDialog extends StatefulWidget {
  const AccountLoginDialog({super.key, required this.controller});
  final NotebookController controller;

  @override
  State<AccountLoginDialog> createState() => _AccountLoginDialogState();
}

class _AccountLoginDialogState extends State<AccountLoginDialog> {
  final _mobileForm = GlobalKey<FormState>();
  final _otpForm = GlobalKey<FormState>();
  final _nameForm = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _otp = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  _LoginStep _step = _LoginStep.mobile;
  String? _challenge;
  String? _testOtp;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _mobile.dispose();
    _otp.dispose();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  String _asciiDigits(String value) => value
      .replaceAll('۰', '0')
      .replaceAll('۱', '1')
      .replaceAll('۲', '2')
      .replaceAll('۳', '3')
      .replaceAll('۴', '4')
      .replaceAll('۵', '5')
      .replaceAll('۶', '6')
      .replaceAll('۷', '7')
      .replaceAll('۸', '8')
      .replaceAll('۹', '9')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');

  String _normalizedMobile(String value) =>
      _asciiDigits(value).trim().replaceAll(RegExp(r'[\s()\-]'), '');

  String? _validateMobile(String? value) {
    final mobile = _normalizedMobile(value ?? '');
    if (mobile.isEmpty) return 'شمارهٔ موبایل را وارد کنید.';
    if (!RegExp(r'^(?:\+98|0098|0)?9[0-9]{9}$').hasMatch(mobile)) {
      return 'شمارهٔ موبایل را به شکل ۰۹۱۲۳۴۵۶۷۸۹ وارد کنید.';
    }
    return null;
  }

  String? _validateOtp(String? value) {
    final otp = _asciiDigits(value ?? '').trim();
    if (otp.isEmpty) return 'کد یک‌بارمصرف را وارد کنید.';
    if (!RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
      return 'کد باید دقیقاً ۶ رقم باشد.';
    }
    return null;
  }

  String? _validateName(String? value, String label) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '$label را وارد کنید.';
    if (name.length < 2 || name.length > 60) {
      return '$label باید بین ۲ تا ۶۰ نویسه باشد.';
    }
    if (!RegExp(
      r'^[\u0600-\u06FFa-zA-Z]+(?:[ \u200c\u200f\u0640\x27\-][\u0600-\u06FFa-zA-Z]+)*$',
    ).hasMatch(name)) {
      return '$label را با حروف وارد کنید.';
    }
    return null;
  }

  Future<void> _requestCode() async {
    if (!(_mobileForm.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.startAccountOtp(
        _normalizedMobile(_mobile.text),
      );
      if (!mounted) return;
      final challenge = result['challenge_id'] as String?;
      final testOtp = result['test_otp'] as String?;
      if (challenge == null || testOtp == null) {
        setState(() => _error = 'کد ورود از سرور دریافت نشد.');
        return;
      }
      setState(() {
        _challenge = challenge;
        _testOtp = testOtp;
        _otp.clear();
        _step = _LoginStep.otp;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (!(_otpForm.currentState?.validate() ?? false)) return;
    final challenge = _challenge;
    if (challenge == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.verifyAccountOtp(
        challenge,
        _asciiDigits(_otp.text).trim(),
      );
      if (result['needs_name'] == true) {
        if (mounted) setState(() => _step = _LoginStep.name);
        return;
      }
      if (widget.controller.isSignedIn && mounted) {
        Navigator.pop(context, true);
      } else if (mounted) {
        setState(() => _error = 'ورود از سرور تأیید نشد.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishRegistration() async {
    if (!(_nameForm.currentState?.validate() ?? false)) return;
    final challenge = _challenge;
    if (challenge == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fullName = '${_firstName.text.trim()} ${_lastName.text.trim()}';
      await widget.controller.verifyAccountOtp(
        challenge,
        _asciiDigits(_otp.text).trim(),
        name: fullName,
      );
      if (widget.controller.isSignedIn && mounted) {
        Navigator.pop(context, true);
      } else if (mounted) {
        setState(() => _error = 'ساخت حساب از سرور تأیید نشد.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  String get _title => switch (_step) {
    _LoginStep.mobile => 'ورود یا ساخت حساب',
    _LoginStep.otp => 'تأیید شمارهٔ موبایل',
    _LoginStep.name => 'تکمیل اطلاعات حساب',
  };

  String get _description => switch (_step) {
    _LoginStep.mobile => 'شمارهٔ موبایل خود را وارد کنید تا کد ورود بفرستیم.',
    _LoginStep.otp => 'کد ارسال‌شده به ${_mobile.text.trim()} را وارد کنید.',
    _LoginStep.name => 'کد تأیید شد. نام و نام خانوادگی‌تان را وارد کنید.',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_title),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_description),
            const SizedBox(height: 16),
            if (_step == _LoginStep.mobile)
              Form(
                key: _mobileForm,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: TextFormField(
                  key: const Key('account-mobile'),
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  maxLength: 16,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  validator: _validateMobile,
                  decoration: const InputDecoration(
                    labelText: 'شمارهٔ موبایل',
                    hintText: '۰۹۱۲۳۴۵۶۷۸۹',
                    counterText: '',
                  ),
                ),
              )
            else if (_step == _LoginStep.otp)
              Form(
                key: _otpForm,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_testOtp != null) ...[
                      Text(
                        'کد آزمایشی ورود',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      SelectableText(
                        _testOtp!,
                        key: const Key('account-test-otp'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        'تا زمان اتصال پنل پیامکی، کد در همین برنامه نمایش داده می‌شود.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const Key('account-otp'),
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      validator: _validateOtp,
                      decoration: const InputDecoration(
                        labelText: 'کد شش‌رقمی',
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              )
            else
              Form(
                key: _nameForm,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('account-first-name'),
                      controller: _firstName,
                      textDirection: TextDirection.rtl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 60,
                      validator: (value) => _validateName(value, 'نام'),
                      decoration: const InputDecoration(
                        labelText: 'نام',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('account-last-name'),
                      controller: _lastName,
                      textDirection: TextDirection.rtl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 60,
                      validator: (value) =>
                          _validateName(value, 'نام خانوادگی'),
                      decoration: const InputDecoration(
                        labelText: 'نام خانوادگی',
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('account-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('انصراف'),
      ),
      if (_step != _LoginStep.mobile)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _step = _LoginStep.mobile;
                  _challenge = null;
                  _testOtp = null;
                  _error = null;
                }),
          child: const Text('تغییر شماره'),
        ),
      FilledButton(
        key: Key(switch (_step) {
          _LoginStep.mobile => 'account-request-otp',
          _LoginStep.otp => 'account-verify-otp',
          _LoginStep.name => 'account-finish-registration',
        }),
        onPressed: _busy
            ? null
            : switch (_step) {
                _LoginStep.mobile => _requestCode,
                _LoginStep.otp => _verifyOtp,
                _LoginStep.name => _finishRegistration,
              },
        child: Text(
          _busy
              ? 'لطفاً صبر کنید…'
              : switch (_step) {
                  _LoginStep.mobile => 'دریافت کد',
                  _LoginStep.otp => 'تأیید کد',
                  _LoginStep.name => 'ساخت حساب و ورود',
                },
        ),
      ),
    ],
  );
}
