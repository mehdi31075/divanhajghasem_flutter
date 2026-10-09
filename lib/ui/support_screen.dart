import 'package:flutter/material.dart';
import '../application/app_config.dart';
import '../application/notebook_controller.dart';
import 'account_login_dialog.dart';
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
  final List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  bool _loading = false;
  bool _composerOpen = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _composerOpen = !widget.controller.isSignedIn;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.isSignedIn) _refresh();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final token = widget.controller.accountToken;
    if (token == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await widget.controller.library.api.supportMessages(
        token,
      );
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(messages);
        });
      }
    } catch (error) {
      if (!mounted) return;
      final message = _messageOf(error);
      setState(() => _error = message);
      if (message.contains('وارد حساب شوید') || message.contains('منقضی')) {
        await widget.controller.logoutAccount();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'متن پیام را بنویسید.');
      return;
    }
    if (!widget.controller.isSignedIn) {
      final loggedIn = await showDialog<bool>(
        context: context,
        builder: (_) => AccountLoginDialog(controller: widget.controller),
      );
      if (loggedIn != true || !mounted) return;
    }
    final token = widget.controller.accountToken;
    if (token == null) return;
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.controller.library.api.submitSupportMessage(token, text);
      if (!mounted) return;
      _message.clear();
      setState(() {
        _notice = 'درخواست ثبت شد؛ پاسخ مدیر را در همین گفت‌وگو می‌بینید.';
        _composerOpen = false;
      });
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      final message = _messageOf(error);
      setState(() => _error = message);
      if (message.contains('وارد حساب شوید') || message.contains('منقضی')) {
        await widget.controller.logoutAccount();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendReply(String ticketId, String text) async {
    final token = widget.controller.accountToken;
    if (token == null) return;
    try {
      await widget.controller.library.api.submitSupportReply(
        token,
        ticketId,
        text,
      );
      if (!mounted) return;
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      final message = _messageOf(error);
      setState(() => _error = message);
      if (message.contains('وارد حساب شوید') || message.contains('منقضی')) {
        await widget.controller.logoutAccount();
      }
      rethrow;
    }
  }

  String _messageOf(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PageBody(
      key: const Key('support-page'),
      children: [
        Text('پشتیبانی', style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'انتقاد، پیشنهاد یا پرسش خود را متنی بنویسید. پاسخ مدیر در همین بخش نمایش داده می‌شود.',
        ),
        if (widget.controller.isSignedIn) _accountCard(),
        if (widget.controller.isSignedIn) _ticketsHeading(),
        if (_composerOpen) _composerCard(),
        if (_notice != null)
          SoftMessage(
            title: 'پشتیبانی',
            message: _notice!,
            icon: Icons.check_circle_outline,
          ),
        if (_error != null)
          SoftMessage(
            title: 'انجام نشد',
            message: _error!,
            icon: Icons.error_outline,
            isError: true,
          ),
        if (widget.controller.isSignedIn) ...[
          if (_messages.isEmpty && !_loading)
            const SoftMessage(
              title: 'درخواستی ندارید',
              message:
                  'درخواست‌های ثبت‌شده و پاسخ پشتیبانی اینجا نمایش داده می‌شوند.',
              icon: Icons.mark_chat_unread_outlined,
            ),
          for (final message in _messages) _ticketCard(message),
        ],
      ],
    ),
  );

  Widget _ticketsHeading() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'درخواست‌های من',
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
      if (!_composerOpen)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.tonalIcon(
            key: const Key('support-new-ticket'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
            onPressed: () => setState(() {
              _message.clear();
              _composerOpen = true;
            }),
            icon: const Icon(Icons.add),
            label: const Text('درخواست جدید'),
          ),
        ),
    ],
  );

  Widget _accountCard() => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: NotebookColors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'حساب: ${widget.controller.accountUser?['name'] ?? widget.controller.accountUser?['mobile'] ?? 'وارد شده'}',
            ),
          ),
          IconButton(
            tooltip: 'خروج از حساب',
            onPressed: _sending
                ? null
                : () => widget.controller.logoutAccount(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    ),
  );

  Widget _composerCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'درخواست تازه',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (widget.controller.isSignedIn)
                IconButton(
                  tooltip: 'بستن فرم',
                  onPressed: _sending
                      ? null
                      : () => setState(() => _composerOpen = false),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          TextField(
            key: const Key('support-message'),
            controller: _message,
            minLines: 4,
            maxLines: 8,
            maxLength: 3000,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'متن پیام',
              hintText: 'انتقاد، پیشنهاد یا پرسش خود را بنویسید…',
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
            label: Text(_sending ? 'در حال ثبت…' : 'ثبت درخواست'),
          ),
          if (!widget.controller.isSignedIn)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('برای ثبت درخواست، ورود با شمارهٔ موبایل لازم است.'),
            ),
        ],
      ),
    ),
  );

  Widget _ticketCard(Map<String, dynamic> message) {
    final id = message['id']?.toString() ?? '';
    final createdAt = message['created_at'];
    final date = _formatDate(createdAt);

    final thread = <Map<String, dynamic>>[
      {
        'sender': 'user',
        'message': message['message']?.toString() ?? '',
        'created_at': createdAt,
      },
    ];
    final rawReplies = message['replies'];
    if (rawReplies is List && rawReplies.isNotEmpty) {
      for (final r in rawReplies.whereType<Map>()) {
        thread.add(Map<String, dynamic>.from(r));
      }
    } else {
      final reply = message['reply']?.toString();
      if (reply?.trim().isNotEmpty == true) {
        thread.add({
          'sender': 'admin',
          'message': reply!,
          'created_at': message['replied_at'],
        });
      }
    }

    final lastEntry = thread.last;
    final lastIsAdmin = lastEntry['sender'] == 'admin';
    final status = lastIsAdmin ? 'پاسخ داده شده' : 'در انتظار پاسخ';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('support-ticket-$id'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        title: Text('درخواست پشتیبانی ${id.isEmpty ? '' : '· $id'}'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$status${date.isEmpty ? '' : ' · $date'}'),
        ),
        children: [
          for (int i = 0; i < thread.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            if (thread[i]['sender'] == 'admin')
              _chatBubble(
                label: AppConfig.supportLabel,
                text: thread[i]['message']?.toString() ?? '',
                date: _formatDate(thread[i]['created_at']),
                alignment: AlignmentDirectional.centerStart,
                background: Colors.white,
              )
            else
              _chatBubble(
                label: 'شما',
                text: thread[i]['message']?.toString() ?? '',
                date: _formatDate(thread[i]['created_at']),
                alignment: AlignmentDirectional.centerEnd,
                background: NotebookColors.soft,
              ),
          ],
          const SizedBox(height: 12),
          if (!lastIsAdmin) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NotebookColors.ivory,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NotebookColors.border),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 20,
                      color: NotebookColors.muted,
                    ),
                    SizedBox(width: 8),
                    Text('در انتظار پاسخ پشتیبانی'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _TicketReplyComposer(
            key: Key('ticket-reply-composer-$id'),
            ticketId: id,
            onSend: (text) => _sendReply(id, text),
          ),
        ],
      ),
    );
  }

  Widget _chatBubble({
    required String label,
    required String text,
    required String date,
    required AlignmentGeometry alignment,
    required Color background,
  }) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NotebookColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: NotebookColors.teal),
            ),
            const SizedBox(height: 6),
            SelectableText(text),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                date,
                textAlign: TextAlign.end,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: NotebookColors.muted),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  String _formatDate(Object? raw) {
    final value = raw?.toString();
    if (value == null) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    return widget.controller.dateService.formatDateTime(date);
  }
}

class _TicketReplyComposer extends StatefulWidget {
  const _TicketReplyComposer({
    super.key,
    required this.ticketId,
    required this.onSend,
  });

  final String ticketId;
  final Future<void> Function(String text) onSend;

  @override
  State<_TicketReplyComposer> createState() => _TicketReplyComposerState();
}

class _TicketReplyComposerState extends State<_TicketReplyComposer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      if (mounted) _controller.clear();
    } catch (_) {
      // Retain typed text on error for user retry per AGENTS.md rule
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: NotebookColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: Key('support-ticket-reply-input-${widget.ticketId}'),
          controller: _controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 3000,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            hintText: 'پاسخ شما به این گفتگو…',
            counterText: '',
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            key: Key('support-ticket-reply-send-${widget.ticketId}'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(140, 64),
            ),
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_sending ? 'در حال ارسال…' : 'ارسال پاسخ'),
          ),
        ),
      ],
    ),
  );
}
