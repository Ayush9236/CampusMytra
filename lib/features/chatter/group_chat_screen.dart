import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';

final _sb = Supabase.instance.client;

const _gIndigo = Color(0xFF818CF8);
const _gPink   = Color(0xFFE879F9);

// ══════════════════════════════════════════════════════════════════════════════
// GROUP CHAT SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class GroupChatScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final String groupEmoji;
  final int memberCount;

  const GroupChatScreen({
    Key? key,
    required this.conversationId,
    required this.groupName,
    required this.groupEmoji,
    required this.memberCount,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _myId   = _sb.auth.currentUser?.id;
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members  = [];
  bool   _loading     = true;
  bool   _sending     = false;
  int    _memberCount = 0;
  late String _groupName;
  RealtimeChannel? _channel;
  Timer? _pollTimer;
  Timer? _vanishTimer;

  @override
  void initState() {
    super.initState();
    _memberCount = widget.memberCount;
    _groupName   = widget.groupName;
    _loadMessages();
    _loadMembers();
    _subscribe();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) { if (mounted) _loadMessages(silent: true); });
    _vanishTimer = Timer.periodic(
        const Duration(minutes: 1), (_) { if (mounted) _loadMessages(silent: true); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _channel?.unsubscribe();
    _pollTimer?.cancel();
    _vanishTimer?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      final data = await _sb
          .from('messages')
          .select('*, profiles!sender_id(name, avatar_emoji)')
          .eq('conversation_id', widget.conversationId)
          .isFilter('deleted_at', null)
          .or('vanish_at.is.null,vanish_at.gt.$now')
          .order('created_at');
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data as List);
          _loading  = false;
        });
        _scrollToBottom();
        _markRead();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final data = await _sb.rpc('get_group_members',
          params: {'p_conversation_id': widget.conversationId});
      if (mounted) setState(() {
        _members     = List<Map<String, dynamic>>.from(data as List);
        _memberCount = _members.length;
      });
    } catch (_) {}
  }

  void _subscribe() {
    _channel = _sb.channel('group_${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: widget.conversationId),
          callback: (_) => _loadMessages(silent: true))
        .subscribe();
  }

  Future<void> _markRead() async {
    if (_myId == null) return;
    try {
      await _sb.rpc('track_group_read', params: {
        'p_conversation_id': widget.conversationId,
        'p_reader_id': _myId,
      });
    } catch (_) {
      try {
        await _sb.rpc('mark_messages_read', params: {
          'p_conversation_id': widget.conversationId,
          'p_reader_id': _myId,
        });
      } catch (_) {}
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _myId == null || _sending) return;
    _ctrl.clear();
    setState(() => _sending = true);
    try {
      await _sb.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'content': text,
      });
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Message long-press ────────────────────────────────────────────────────

  Future<void> _saveMessage(String messageId) async {
    try {
      await _sb.rpc('save_message', params: {
        'p_message_id': messageId,
        'p_user_id': _myId,
      });
      await _loadMessages(silent: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('💾 Saved — message won\'t vanish'),
              duration: Duration(seconds: 2)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _unsendMessage(String messageId) async {
    try {
      await _sb.from('messages')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', messageId)
          .eq('sender_id', _myId!);
      await _loadMessages(silent: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message unsent'), duration: Duration(seconds: 2)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')));
    }
  }

  void _onLongPress(Map<String, dynamic> msg) {
    final isSaved   = msg['is_saved'] == true;
    final isMe      = msg['sender_id'] == _myId;
    final msgId     = msg['id']?.toString() ?? '';
    final content   = msg['content']?.toString() ?? '';
    final surface   = AppColors.surface(context);
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: subColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.surfaceVariant(context),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(content, style: TextStyle(color: textColor, fontSize: 13),
                  maxLines: 3, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 12),
            _OptionTile(
              icon: Icons.copy_rounded,
              label: 'Copy',
              color: textColor,
              onTap: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied!'), duration: Duration(seconds: 1)));
              }),
            if (!isSaved)
              _OptionTile(
                icon: Icons.bookmark_add_rounded,
                label: 'Save  ·  won\'t vanish',
                color: _gIndigo,
                onTap: () { Navigator.pop(context); _saveMessage(msgId); }),
            if (isSaved)
              _OptionTile(
                icon: Icons.bookmark_added_rounded,
                label: 'Already saved',
                color: _gIndigo,
                onTap: () => Navigator.pop(context)),
            if (isMe)
              _OptionTile(
                icon: Icons.delete_sweep_rounded,
                label: 'Unsend',
                color: Colors.red,
                onTap: () { Navigator.pop(context); _unsendMessage(msgId); }),
            const SizedBox(height: 8),
          ]))));
  }

  // ── Group management ──────────────────────────────────────────────────────

  Future<void> _changeGroupName() async {
    final ctrl     = TextEditingController(text: _groupName);
    final textColor = AppColors.text(context);
    final surface   = AppColors.surface(context);
    final subColor  = AppColors.textSecondary(context);
    final border    = AppColors.border(context);
    final sv        = AppColors.surfaceVariant(context);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Group',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: textColor),
          maxLength: 30,
          decoration: InputDecoration(
            hintText: 'Group name...',
            hintStyle: TextStyle(color: subColor),
            filled: true,
            fillColor: sv,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: border)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: _gIndigo, width: 2)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save',
                  style: TextStyle(color: _gIndigo, fontWeight: FontWeight.w800))),
        ]));

    ctrl.dispose();
    if (newName == null || newName.isEmpty || newName == _groupName) return;
    try {
      await _sb.rpc('update_group_name', params: {
        'p_conversation_id': widget.conversationId,
        'p_new_name': newName,
        'p_requester_id': _myId,
      });
      if (mounted) setState(() => _groupName = newName);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group renamed!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _removeMember(String userId, String name) async {
    final isMe = userId == _myId;
    final surface  = AppColors.surface(context);
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isMe ? 'Leave Group' : 'Remove Member',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        content: Text(isMe ? 'Leave "$_groupName"?' : 'Remove $name from the group?',
            style: TextStyle(color: subColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(isMe ? 'Leave' : 'Remove',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800))),
        ]));

    if (confirmed != true) return;
    try {
      await _sb.rpc('remove_group_member', params: {
        'p_conversation_id': widget.conversationId,
        'p_user_id': userId,
        'p_requester_id': _myId,
      });
      if (isMe && mounted) {
        Navigator.pop(context);
      } else {
        await _loadMembers();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name removed')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _showAddMembers() async {
    final existingIds = _members.map((m) => m['user_id']?.toString() ?? '').toSet();
    List<Map<String, dynamic>> friends = [];
    try {
      final data = await _sb.rpc('get_my_friends', params: {'p_user_id': _myId});
      friends = List<Map<String, dynamic>>.from(data as List)
          .where((f) => !existingIds.contains(f['friend_id']?.toString()))
          .toList();
    } catch (_) {}
    if (!mounted) return;

    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final surface   = AppColors.surface(context);
    final border    = AppColors.border(context);
    final selected  = <String>{};

    await showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(children: [
                Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: subColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(children: [
                  ShaderMask(
                    shaderCallback: (b) =>
                        const LinearGradient(colors: [_gIndigo, _gPink]).createShader(b),
                    child: const Text('Add Members', style: TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                  const Spacer(),
                  if (selected.isNotEmpty)
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        int added = 0;
                        for (final uid in selected) {
                          try {
                            await _sb.rpc('add_group_member', params: {
                              'p_conversation_id': widget.conversationId,
                              'p_new_user_id': uid,
                              'p_requester_id': _myId,
                            });
                            added++;
                          } catch (_) {}
                        }
                        await _loadMembers();
                        if (mounted && added > 0) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  '$added member${added == 1 ? '' : 's'} added!')));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [_gIndigo, _gPink]),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('Add ${selected.length}', style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)))),
                ]),
              ])),
            Expanded(
              child: friends.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('😊', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text('All friends are already in the group!',
                          style: TextStyle(color: subColor, fontSize: 14),
                          textAlign: TextAlign.center),
                    ])))
                : ListView.builder(
                    controller: sc,
                    itemCount: friends.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (_, i) {
                      final f    = friends[i];
                      final id   = f['friend_id']?.toString() ?? '';
                      final name = f['name']?.toString() ?? 'Unknown';
                      final emoj = f['avatar_emoji']?.toString() ?? '🎓';
                      final sel  = selected.contains(id);
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setLocal(() {
                            if (sel) selected.remove(id); else selected.add(id);
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: sel ? _gIndigo.withOpacity(0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: sel ? _gIndigo.withOpacity(0.5) : border,
                                width: sel ? 1.5 : 1)),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  _gIndigo.withOpacity(sel ? 0.4 : 0.15),
                                  _gPink.withOpacity(sel ? 0.4 : 0.15)]),
                                borderRadius: BorderRadius.circular(12)),
                              child: Center(child: Text(emoj,
                                  style: const TextStyle(fontSize: 20)))),
                            const SizedBox(width: 12),
                            Expanded(child: Text(name, style: TextStyle(
                                color: textColor, fontWeight: FontWeight.w700, fontSize: 15))),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: sel
                                    ? const LinearGradient(colors: [_gIndigo, _gPink])
                                    : null,
                                border: sel ? null : Border.all(color: border, width: 2)),
                              child: sel
                                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                                  : null),
                          ])));
                    }),
            ),
            const SizedBox(height: 20),
          ]))));
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, _) {
          final textColor = AppColors.text(context);
          final subColor  = AppColors.textSecondary(context);
          final sv        = AppColors.surfaceVariant(context);

          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, sc) => ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: subColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),

                // Avatar
                Center(child: Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_gIndigo, _gPink]),
                      borderRadius: BorderRadius.circular(26)),
                  child: Center(child: Text(widget.groupEmoji,
                      style: const TextStyle(fontSize: 38))))),
                const SizedBox(height: 16),

                // Name + rename button
                Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(_groupName, style: TextStyle(
                      color: textColor, fontSize: 22, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _changeGroupName();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: _gIndigo.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.edit_rounded, color: _gIndigo, size: 16))),
                ])),
                const SizedBox(height: 6),
                Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: _gIndigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$_memberCount members',
                      style: const TextStyle(color: _gIndigo, fontSize: 12, fontWeight: FontWeight.w600)))),
                const SizedBox(height: 24),

                // Add members
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _showAddMembers();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_gIndigo, _gPink]),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Add Members', style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    ]))),
                const SizedBox(height: 24),

                // Members list header
                Text('Members', style: TextStyle(
                    color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),

                ..._members.map((m) {
                  final memberId = m['user_id']?.toString() ?? '';
                  final name     = m['name']?.toString() ?? 'Unknown';
                  final emoji    = m['avatar_emoji']?.toString() ?? '🎓';
                  final isMe     = memberId == _myId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: sv, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            _gIndigo.withOpacity(0.2), _gPink.withOpacity(0.2)]),
                          borderRadius: BorderRadius.circular(12)),
                        child: Center(child: Text(emoji,
                            style: const TextStyle(fontSize: 20)))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(name, style: TextStyle(
                            color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                        if (isMe) const Text('You',
                            style: TextStyle(color: _gIndigo, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ])),
                      GestureDetector(
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _removeMember(memberId, name);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(
                              isMe ? Icons.exit_to_app_rounded : Icons.person_remove_outlined,
                              color: Colors.red.withOpacity(0.7), size: 18))),
                    ]));
                }),
              ]));
        }));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatTime(dynamic raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw.toString())?.toLocal();
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String? _vanishCountdown(dynamic raw) {
    if (raw == null) return null;
    final vanishAt = DateTime.tryParse(raw.toString())?.toLocal();
    if (vanishAt == null) return null;
    final diff = vanishAt.difference(DateTime.now());
    if (diff.isNegative) return null;
    if (diff.inHours > 0) return '🕐 ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    return '🕐 ${diff.inMinutes}m';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark    = AppColors.isDark(context);
    final surface   = AppColors.surface(context);
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final bg        = AppColors.background(context);
    final border    = AppColors.border(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leadingWidth: 40,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textColor, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: GestureDetector(
          onTap: _showGroupInfo,
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_gIndigo, _gPink]),
                borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(widget.groupEmoji,
                  style: const TextStyle(fontSize: 20)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_groupName, style: TextStyle(
                  color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
              Text('$_memberCount members · tap for info',
                  style: TextStyle(color: subColor, fontSize: 10)),
            ])),
          ])),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: subColor, size: 22),
            onPressed: _showGroupInfo),
        ]),
      body: Column(children: [
        Expanded(
          child: _loading
            ? Center(child: CircularProgressIndicator(color: _gIndigo, strokeWidth: 2))
            : _messages.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(widget.groupEmoji, style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text('No messages yet', style: TextStyle(
                      color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Be the first to say hi! 👋',
                      style: TextStyle(color: subColor, fontSize: 13)),
                ]))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg        = _messages[i];
                    final isMe       = msg['sender_id'] == _myId;
                    final senderName = msg['profiles']?['name']?.toString() ?? 'Unknown';
                    final senderEmoji= msg['profiles']?['avatar_emoji']?.toString() ?? '🎓';
                    final content    = msg['content']?.toString() ?? '';
                    final time       = _formatTime(msg['created_at']);
                    final isSaved    = msg['is_saved'] == true;
                    final vanishStr  = _vanishCountdown(msg['vanish_at']);
                    final showSender = !isMe && (i == 0 ||
                        _messages[i - 1]['sender_id'] != msg['sender_id']);

                    return GestureDetector(
                      onLongPress: () => _onLongPress(msg),
                      child: _GroupMessageBubble(
                        content:     content,
                        isMe:        isMe,
                        senderName:  senderName,
                        senderEmoji: senderEmoji,
                        time:        time,
                        showSender:  showSender,
                        isDark:      isDark,
                        surface:     surface,
                        textColor:   textColor,
                        subColor:    subColor,
                        border:      border,
                        isSaved:     isSaved,
                        vanishStr:   vanishStr,
                      ));
                  })),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(
              color: bg, border: Border(top: BorderSide(color: border))),
          child: Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: border)),
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Message $_groupName...',
                    hintStyle: TextStyle(color: subColor, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10)),
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  maxLines: 4,
                  minLines: 1))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_gIndigo, _gPink]),
                    borderRadius: BorderRadius.circular(14)),
                child: _sending
                  ? const Center(child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18))),
          ])),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OPTION TILE
// ══════════════════════════════════════════════════════════════════════════════
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 20)),
      title: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      onTap: onTap);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GROUP MESSAGE BUBBLE
// ══════════════════════════════════════════════════════════════════════════════
class _GroupMessageBubble extends StatelessWidget {
  final String content, senderName, senderEmoji, time;
  final bool isMe, showSender, isDark;
  final Color surface, textColor, subColor, border;
  final bool isSaved;
  final String? vanishStr;

  const _GroupMessageBubble({
    required this.content,
    required this.isMe,
    required this.senderName,
    required this.senderEmoji,
    required this.time,
    required this.showSender,
    required this.isDark,
    required this.surface,
    required this.textColor,
    required this.subColor,
    required this.border,
    required this.isSaved,
    this.vanishStr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: 4,
          top: showSender ? 12 : 2,
          left: isMe ? 56 : 0,
          right: isMe ? 0 : 56),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender && !isMe)
            Padding(
              padding: const EdgeInsets.only(left: 38, bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(senderEmoji, style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                Text(senderName, style: const TextStyle(
                    color: _gIndigo, fontSize: 11, fontWeight: FontWeight.w700)),
              ])),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                Container(
                  width: 30, height: 30,
                  margin: const EdgeInsets.only(right: 6, bottom: 2),
                  decoration: BoxDecoration(
                    gradient: showSender
                      ? LinearGradient(colors: [
                          _gIndigo.withOpacity(0.3), _gPink.withOpacity(0.3)])
                      : null,
                    borderRadius: BorderRadius.circular(10)),
                  child: showSender
                    ? Center(child: Text(senderEmoji,
                        style: const TextStyle(fontSize: 15)))
                    : null),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isMe
                      ? const LinearGradient(
                          colors: [_gIndigo, _gPink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight)
                      : null,
                    color: isMe ? null : surface,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18)),
                    border: isMe ? null : Border.all(color: border)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(content, style: TextStyle(
                          color: isMe ? Colors.white : textColor,
                          fontSize: 14, height: 1.4)),
                      const SizedBox(height: 4),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(time, style: TextStyle(
                            color: isMe ? Colors.white54 : subColor, fontSize: 10)),
                        if (isSaved) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.bookmark_rounded,
                              color: isMe ? Colors.white54 : _gIndigo, size: 11),
                        ],
                        if (vanishStr != null && !isSaved) ...[
                          const SizedBox(width: 4),
                          Text(vanishStr!, style: TextStyle(
                              color: isMe ? Colors.white54 : Colors.orange.shade300,
                              fontSize: 9)),
                        ],
                      ]),
                    ]))),
            ]),
        ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CREATE GROUP SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _myId     = _sb.auth.currentUser?.id;
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _friends  = [];
  final Set<String>          _selected = {};
  String _emoji    = '👥';
  bool   _loading  = true;
  bool   _creating = false;

  static const _emojis = [
    '👥', '🎓', '🚀', '🎮', '🏆', '🎉', '🌟', '🔥', '💡', '🎯',
    '🎸', '⚽', '🧠', '📚', '🌈', '🎨', '🤝', '💬', '🌙', '☕',
  ];

  @override
  void initState() { super.initState(); _loadFriends(); }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _loadFriends() async {
    if (_myId == null) return;
    try {
      final data = await _sb.rpc('get_my_friends', params: {'p_user_id': _myId});
      if (mounted) setState(() {
        _friends = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a group name')));
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one member')));
      return;
    }
    setState(() => _creating = true);
    try {
      final convId = await _sb.rpc('create_group_conversation', params: {
        'p_creator_id': _myId,
        'p_group_name': name,
        'p_group_emoji': _emoji,
        'p_member_ids': _selected.toList(),
      });
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            conversationId: convId.toString(),
            groupName:      name,
            groupEmoji:     _emoji,
            memberCount:    _selected.length + 1,
          )));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create group: $e')));
      }
    }
  }

  void _pickEmoji() {
    final surface   = AppColors.surface(context);
    final textColor = AppColors.text(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Pick a group emoji', style: TextStyle(
                color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: _emojis.map((e) => GestureDetector(
                onTap: () {
                  setState(() => _emoji = e);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: _emoji == e ? _gIndigo.withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _emoji == e ? _gIndigo : Colors.grey.withOpacity(0.2),
                        width: _emoji == e ? 2 : 1)),
                  child: Center(child: Text(e,
                      style: const TextStyle(fontSize: 26)))))).toList()),
            const SizedBox(height: 12),
          ]))));
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final surface   = AppColors.surface(context);
    final bg        = AppColors.background(context);
    final border    = AppColors.border(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: textColor),
          onPressed: () => Navigator.pop(context)),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
              colors: [_gIndigo, _gPink]).createShader(b),
          child: const Text('New Group', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white))),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _creating ? null : _createGroup,
              child: _creating
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _gIndigo))
                : const Text('Create', style: TextStyle(
                    color: _gIndigo, fontWeight: FontWeight.w800, fontSize: 15)))),
        ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [
            GestureDetector(
              onTap: _pickEmoji,
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    _gIndigo.withOpacity(0.15), _gPink.withOpacity(0.15)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gIndigo.withOpacity(0.5), width: 1.5)),
                child: Stack(alignment: Alignment.center, children: [
                  Text(_emoji, style: const TextStyle(fontSize: 30)),
                  Positioned(right: 4, bottom: 4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(
                          color: _gIndigo, shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 9))),
                ]))),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'Group name...',
                  hintStyle: TextStyle(color: subColor),
                  filled: true,
                  fillColor: surface,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border)),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide(color: _gIndigo, width: 2))),
                maxLength: 30)),
          ])),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(children: [
            Text('Add Members', style: TextStyle(
                color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (_selected.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_gIndigo, _gPink]),
                  borderRadius: BorderRadius.circular(12)),
                child: Text('${_selected.length} selected', style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
          ])),

        Expanded(
          child: _loading
            ? Center(child: CircularProgressIndicator(color: _gIndigo, strokeWidth: 2))
            : _friends.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('😶', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text('No friends to add yet', style: TextStyle(color: subColor, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Add friends first to create a group',
                      style: TextStyle(color: subColor, fontSize: 12)),
                ]))
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (_, i) {
                    final f        = _friends[i];
                    final id       = f['friend_id']?.toString() ?? '';
                    final name     = f['name']?.toString() ?? 'Unknown';
                    final emoji    = f['avatar_emoji']?.toString() ?? '🎓';
                    final selected = _selected.contains(id);

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (selected) _selected.remove(id);
                          else _selected.add(id);
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected ? _gIndigo.withOpacity(0.08) : surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: selected ? _gIndigo.withOpacity(0.5) : border,
                              width: selected ? 1.5 : 1)),
                        child: Row(children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                _gIndigo.withOpacity(selected ? 0.4 : 0.15),
                                _gPink.withOpacity(selected ? 0.4 : 0.15)]),
                              borderRadius: BorderRadius.circular(14)),
                            child: Center(child: Text(emoji,
                                style: const TextStyle(fontSize: 22)))),
                          const SizedBox(width: 12),
                          Expanded(child: Text(name, style: TextStyle(
                              color: textColor, fontWeight: FontWeight.w700, fontSize: 15))),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: selected
                                ? const LinearGradient(colors: [_gIndigo, _gPink])
                                : null,
                              border: selected ? null : Border.all(color: border, width: 2)),
                            child: selected
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                              : null),
                        ])));
                  })),
      ]));
  }
}
