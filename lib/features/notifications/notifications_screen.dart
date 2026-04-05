import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';

// ── Simple relative time formatter ──
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60)  return 'just now';
  if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)    return '${diff.inHours}h ago';
  if (diff.inDays < 7)      return '${diff.inDays}d ago';
  if (diff.inDays < 30)     return '${(diff.inDays / 7).floor()}w ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

// ══════════════════════════════════════════════════════════════════════════════
// NOTIFICATIONS SCREEN — in-app inbox
// ══════════════════════════════════════════════════════════════════════════════

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _sb
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
      // Mark all as read after loading
      await _sb
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    HapticFeedback.lightImpact();
    try {
      await _sb
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid);
      setState(() {
        _notifications = _notifications
            .map((n) => {...n, 'is_read': true})
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _deleteAll() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear all?',
            style: TextStyle(color: AppColors.text(context))),
        content: Text('Delete all notifications?',
            style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    HapticFeedback.mediumImpact();
    try {
      await _sb.from('notifications').delete().eq('user_id', uid);
      setState(() => _notifications.clear());
    } catch (_) {}
  }

  // ── Icon + color by notification type ──
  _NotifStyle _style(String type) {
    switch (type) {
      case 'like':           return _NotifStyle('❤️', const Color(0xFFFF375F));
      case 'comment':        return _NotifStyle('💬', const Color(0xFF3B82F6));
      case 'college_buzz':   return _NotifStyle('📢', const Color(0xFFFFB800));
      case 'friend_request': return _NotifStyle('👋', const Color(0xFF34D399));
      case 'friend_accept':  return _NotifStyle('🎉', const Color(0xFF34D399));
      case 'game_invite':    return _NotifStyle('🎮', const Color(0xFF818CF8));
      case 'game_result':    return _NotifStyle('🏆', const Color(0xFFFFB800));
      case 'coins_received': return _NotifStyle('🪙', const Color(0xFFFFD700));
      case 'admin':          return _NotifStyle('📣', const Color(0xFFFF6B35));
      default:               return _NotifStyle('🔔', const Color(0xFF818CF8));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final surface = AppColors.surface(context);
    final text = AppColors.text(context);
    final textSec = AppColors.textSecondary(context);
    final border = AppColors.border(context);
    final unread = _notifications.where((n) => n['is_read'] != true).length;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text('Notifications',
                style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 20)),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF818CF8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$unread',
                    style: TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
        actions: [
          if (_notifications.isNotEmpty) ...[
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: TextStyle(color: Color(0xFF818CF8), fontSize: 13)),
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: textSec, size: 22),
              tooltip: 'Clear all',
              onPressed: _deleteAll,
            ),
          ],
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)))
          : _notifications.isEmpty
              ? _EmptyState(textSec: textSec)
              : RefreshIndicator(
                  color: const Color(0xFF818CF8),
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: _notifications.length,
                    separatorBuilder: (context2, i2) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      final type = n['type']?.toString() ?? '';
                      final style = _style(type);
                      final isRead = n['is_read'] == true;
                      final createdAt = DateTime.tryParse(
                              n['created_at']?.toString() ?? '') ??
                          DateTime.now();

                      return GestureDetector(
                        onTap: () {
                          // Mark single as read
                          if (!isRead) {
                            setState(() => _notifications[i] = {...n, 'is_read': true});
                            _sb.from('notifications')
                                .update({'is_read': true})
                                .eq('id', n['id'].toString())
                                .then((_) {});
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isRead
                                ? surface
                                : style.color.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isRead
                                  ? border
                                  : style.color.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon bubble
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: style.color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(style.emoji,
                                      style: TextStyle(fontSize: 20)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n['title']?.toString() ?? '',
                                            style: TextStyle(
                                              color: text,
                                              fontWeight: isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (!isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(left: 8, top: 4),
                                            decoration: BoxDecoration(
                                              color: style.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      n['body']?.toString() ?? '',
                                      style: TextStyle(
                                          color: textSec, fontSize: 13, height: 1.3),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _timeAgo(createdAt),
                                      style: TextStyle(
                                          color: textSec.withOpacity(0.6),
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotifStyle {
  final String emoji;
  final Color color;
  const _NotifStyle(this.emoji, this.color);
}

class _EmptyState extends StatelessWidget {
  final Color textSec;
  const _EmptyState({required this.textSec});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🔕', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('No notifications yet',
              style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('When someone likes, comments\nor sends you a request, it shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSec, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}
