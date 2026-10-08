import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/notebook_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.controller});
  final NotebookController controller;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _message = TextEditingController();
  final _receiptInput = TextEditingController();
  final List<Map<String, dynamic>> _tickets = [];
  bool _sending = false;
  bool _loading = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _message.dispose();
    _receiptInput.dispose();
    super.dispose();
  }

  Future<List<String>> _receipts() async {
    final saved = await widget.controller.database.preference(
      'support_receipts',
    );
    if (saved == null) return [];
    try {
      return (jsonDecode(saved) as List)
          .whereType<String>()
          .where((value) => RegExp(r'^[a-f0-9]{32}$').hasMatch(value))
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveReceipt(String receipt) async {
    final current = await _receipts();
    current.remove(receipt);
    current.insert(0, receipt);
    await widget.controller.database.setPreference(
      'support_receipts',
      jsonEncode(current.take(30).toList()),
    );
  }

  Future<void> _refresh({bool force = false}) async {
    if (_loading && !force) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final receipts = await _receipts();
      final tickets = <Map<String, dynamic>>[];
      for (final receipt in receipts) {
        try {
          tickets.add({
            ...await widget.controller.library.api.supportTicket(receipt),
            'receipt': receipt,
          });
        } catch (_) {
          // Keep other tickets visible if one is temporarily unavailable.
        }
      }
      if (!mounted) return;
      setState(() {
        _tickets
          ..clear()
          ..addAll(tickets);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'پیام‌ها دریافت نشدند. اتصال اینترنت را بررسی کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addReceipt() async {
    final code = _receiptInput.text.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(code)) {
      setState(() => _error = 'کد پیگیری ۳۲ نویسه‌ای را کامل وارد کنید.');
      return;
    }
    try {
      await widget.controller.library.api.supportTicket(code);
      await _saveReceipt(code);
      _receiptInput.clear();
      await _refresh(force: true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'متن پیام را بنویسید.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    try {
      final receipt = await widget.controller.library.api.submitSupportMessage(
        text,
      );
      await _saveReceipt(receipt);
      if (!mounted) return;
      _message.clear();
      setState(
        () => _notice =
            'پیام شما ارسال شد. کد پیگیری را برای مراجعه از دستگاه دیگر نگه دارید.',
      );
      await _refresh(force: true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    key: const Key('support-page'),
    children: [
      Text('پشتیبانی', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        'انتقاد، پیشنهاد یا پرسش خود را فقط به‌صورت متنی بنویسید. پاسخ مدیر در همین بخش نمایش داده می‌شود.',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('support-message'),
                controller: _message,
                minLines: 5,
                maxLines: 9,
                maxLength: 3000,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'متن پیام',
                  hintText: 'پیام خود را بنویسید…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('support-send'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_sending ? 'در حال ارسال…' : 'ارسال پیام'),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 12),
                SoftMessage(
                  title: 'پیام ارسال شد',
                  message: _notice!,
                  icon: Icons.check_circle_outline,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                SoftMessage(
                  title: 'ارسال انجام نشد',
                  message: _error!,
                  icon: Icons.error_outline,
                  isError: true,
                ),
              ],
            ],
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              'پیام‌های من',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'تازه‌سازی پاسخ‌ها',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اگر کد پیگیری را در دستگاه دیگری دارید، اینجا وارد کنید.',
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('support-receipt'),
                controller: _receiptInput,
                maxLength: 32,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'کد پیگیری',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _addReceipt,
                child: const Text('افزودن پیام با کد پیگیری'),
              ),
            ],
          ),
        ),
      ),
      if (_tickets.isEmpty && !_loading)
        const SoftMessage(
          title: 'پیامی ندارید',
          message: 'پس از ارسال پیام، وضعیت پاسخ آن اینجا نمایش داده می‌شود.',
          icon: Icons.mark_chat_unread_outlined,
        ),
      for (final ticket in _tickets) _ticketCard(ticket),
    ],
  );

  Widget _ticketCard(Map<String, dynamic> ticket) {
    final receipt = ticket['receipt'] as String? ?? '';
    final reply = ticket['reply'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'پیام شما',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: NotebookColors.teal,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(ticket['message']?.toString() ?? ''),
            const SizedBox(height: 14),
            Text(
              reply == null || reply.isEmpty
                  ? 'در انتظار پاسخ مدیر'
                  : 'پاسخ مدیر',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: NotebookColors.teal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              reply?.isNotEmpty == true
                  ? reply!
                  : 'پس از ثبت پاسخ، اینجا نمایش داده می‌شود.',
            ),
            const Divider(height: 26),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'کد پیگیری',
                    style: TextStyle(fontSize: 14, color: NotebookColors.muted),
                  ),
                ),
                Flexible(
                  child: SelectableText(
                    receipt,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'کپی کد پیگیری',
                  onPressed: receipt.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: receipt));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('کد پیگیری کپی شد.'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
