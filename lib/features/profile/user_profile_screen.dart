import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';
import '../badges/badge_system.dart';
import 'friends_screen.dart';
import '../buzz/comment_poll.dart';
import '../buzz/notification_service.dart';
import '../chatter/chatter_screen.dart';

final _sb = Supabase.instance.client;

// ── Full 30-theme list (mirrors profile_screen.dart) ──────────────────────
const List<Map<String, dynamic>> kBannerThemes = [
  {'name': 'Royal',    'colors': [Color(0xFF4C1D95), Color(0xFF6C63FF), Color(0xFF818CF8)]},
  {'name': 'Sapphire', 'colors': [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF60A5FA)]},
  {'name': 'Midnight', 'colors': [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)]},
  {'name': 'Obsidian', 'colors': [Color(0xFF18181B), Color(0xFF27272A), Color(0xFF6C63FF)]},
  {'name': 'Gold',     'colors': [Color(0xFF78350F), Color(0xFFD97706), Color(0xFFFBBF24)]},
  {'name': 'Amber',    'colors': [Color(0xFF92400E), Color(0xFFB45309), Color(0xFFF59E0B)]},
  {'name': 'Copper',   'colors': [Color(0xFF7C2D12), Color(0xFFEA580C), Color(0xFFFB923C)]},
  {'name': 'Crimson',  'colors': [Color(0xFF7F1D1D), Color(0xFFDC2626), Color(0xFFF87171)]},
  {'name': 'Emerald',  'colors': [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF34D399)]},
  {'name': 'Forest',   'colors': [Color(0xFF14532D), Color(0xFF16A34A), Color(0xFF4ADE80)]},
  {'name': 'Teal',     'colors': [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF2DD4BF)]},
  {'name': 'Jade',     'colors': [Color(0xFF166534), Color(0xFF15803D), Color(0xFF86EFAC)]},
  {'name': 'Aurora',   'colors': [Color(0xFF4C1D95), Color(0xFF0F766E), Color(0xFF06B6D4)]},
  {'name': 'Dusk',     'colors': [Color(0xFF6B21A8), Color(0xFFDB2777), Color(0xFFFB7185)]},
  {'name': 'Nebula',   'colors': [Color(0xFF1E1B4B), Color(0xFF7C3AED), Color(0xFFEC4899)]},
  {'name': 'Cosmos',   'colors': [Color(0xFF0C1445), Color(0xFF1D4ED8), Color(0xFF818CF8)]},
  {'name': 'Ocean',    'colors': [Color(0xFF0C4A6E), Color(0xFF0284C7), Color(0xFF38BDF8)]},
  {'name': 'Arctic',   'colors': [Color(0xFF1E3A8A), Color(0xFF0EA5E9), Color(0xFFBAE6FD)]},
  {'name': 'Reef',     'colors': [Color(0xFF065F46), Color(0xFF0891B2), Color(0xFF67E8F9)]},
  {'name': 'Storm',    'colors': [Color(0xFF1E293B), Color(0xFF475569), Color(0xFF94A3B8)]},
  {'name': 'Rose',     'colors': [Color(0xFF881337), Color(0xFFE11D48), Color(0xFFFDA4AF)]},
  {'name': 'Sakura',   'colors': [Color(0xFF9D174D), Color(0xFFDB2777), Color(0xFFF9A8D4)]},
  {'name': 'Mauve',    'colors': [Color(0xFF581C87), Color(0xFFA855F7), Color(0xFFE9D5FF)]},
  {'name': 'Lilac',    'colors': [Color(0xFF4C1D95), Color(0xFF8B5CF6), Color(0xFFC4B5FD)]},
  {'name': 'Slate',    'colors': [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF64748B)]},
  {'name': 'Bronze',   'colors': [Color(0xFF431407), Color(0xFF9A3412), Color(0xFFFC8A4A)]},
  {'name': 'Onyx',     'colors': [Color(0xFF09090B), Color(0xFF18181B), Color(0xFF52525B)]},
  {'name': 'Titanium', 'colors': [Color(0xFF111827), Color(0xFF374151), Color(0xFF9CA3AF)]},
  {'name': 'Neon',     'colors': [Color(0xFF0A0A0A), Color(0xFF6C63FF), Color(0xFF00FFD1)]},
  {'name': 'Inferno',  'colors': [Color(0xFF1C0505), Color(0xFFEF4444), Color(0xFFFBBF24)]},
];

List<Color> _themeColors(int i) =>
    List<Color>.from(kBannerThemes[i % kBannerThemes.length]['colors'] as List);

// ── Palette (matches buzz_screen) ──────────────────────────
const _indigo = Color(0xFF818CF8);
const _pink   = Color(0xFFE879F9);
const _green  = Color(0xFF4ADE80);
const _amber  = Color(0xFFFBBF24);

// ══════════════════════════════════════════════════════════════════════════════
// Entry point — call this from anywhere in the app
// ══════════════════════════════════════════════════════════════════════════════
Future<void> openUserProfile(BuildContext context, String userId) {
  return Navigator.push(context, MaterialPageRoute(
    builder: (_) => UserProfileScreen(userId: userId)));
}

// ══════════════════════════════════════════════════════════════════════════════
// UserProfileScreen
// ══════════════════════════════════════════════════════════════════════════════
class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

enum _FriendStatus { none, pendingSent, pendingReceived, friends }

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _stats;
  int _postCount   = 0;
  bool _loading    = true;
  bool _actionBusy = false;
  List<Map<String, dynamic>> _posts = [];
  bool _postsLoading = true;
  BannerRank _bannerRank = BannerRank.none;

  _FriendStatus _friendStatus = _FriendStatus.none;
  String?       _friendshipId;
  bool          _isBlocked = false;

  String? _myId;
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _myId = _sb.auth.currentUser?.id;
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _load();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _loadPosts() async {
    if (!mounted) return;
    setState(() => _postsLoading = true);
    try {
      final rows = await _sb
          .from('buzz_feed')
          .select('id, content, created_at, likes, comment_count, image_url, is_anonymous')
          .eq('user_id', widget.userId)
          .eq('is_anonymous', false)
          .order('created_at', ascending: false)
          .limit(60);
      if (mounted) {
        setState(() {
          _posts = List<Map<String, dynamic>>.from(
              (rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
          _postsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _loadPosts();
    try {
      final rows = await _sb.rpc('get_user_profile',
          params: {'target_user_id': widget.userId});
      if ((rows as List).isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data = Map<String, dynamic>.from(rows.first as Map);

      final profile = {
        'id':             data['id'],
        'name':           data['name'],
        'username':       data['username'],
        'avatar_emoji':   data['avatar_emoji'],
        'banner_index':   data['banner_index'],
        'bio':            data['bio'],
        'college_name':   data['college_name'],
        'branch_name':    data['branch_name'],
        'branch':         data['branch'],
        'created_at':     data['created_at'],
        'college_status': data['college_status'],
        'friend_count':   data['friend_count'] ?? 0,
      };
      final stats = {
        'games_played':    data['games_played']    ?? 0,
        'games_won':       data['games_won']       ?? 0,
        'games_lost':      data['games_lost']      ?? 0,
        'win_streak':      data['win_streak']      ?? 0,
        'best_win_streak': data['best_win_streak'] ?? 0,
      };
      final postCount = (data['post_count'] as num?)?.toInt() ?? 0;

      if (_myId != null && _myId != widget.userId) {
        try {
          final fRows = await _sb.rpc('get_friendship_status',
              params: {'other_user_id': widget.userId});
          if ((fRows as List).isNotEmpty) {
            final row     = fRows.first as Map<String, dynamic>;
            _friendshipId = row['friendship_id']?.toString();
            final st      = row['fstatus']?.toString();
            final iSender = row['i_am_sender'] as bool? ?? false;
            if (st == 'accepted') {
              _friendStatus = _FriendStatus.friends;
            } else if (st == 'pending') {
              _friendStatus = iSender
                  ? _FriendStatus.pendingSent
                  : _FriendStatus.pendingReceived;
            }
          }
        } catch (_) {}

        // Check block status
        try {
          final bRow = await _sb.from('blocked_users')
              .select('id')
              .eq('blocker_id', _myId!)
              .eq('blocked_id', widget.userId)
              .maybeSingle();
          _isBlocked = bRow != null;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _profile   = profile;
        _stats     = stats;
        _postCount = postCount;
        _loading   = false;
      });
      _animCtrl.forward(from: 0);

      try {
        final bResult = await _sb.rpc('get_user_badge_data',
            params: {'p_user_id': widget.userId});
        if (bResult != null) {
          final bRow = (bResult is List && bResult.isNotEmpty)
              ? Map<String, dynamic>.from(bResult.first as Map)
              : Map<String, dynamic>.from(bResult as Map);
          final br = computeBannerRank({
            'user_id':        widget.userId,
            'admin_role':     bRow['admin_role'],
            'signup_rank':    (bRow['signup_rank'] as num?)?.toInt() ?? 999999,
            'uno_wins':       (bRow['uno_wins']       as num?)?.toInt() ?? 0,
            'dsa_wins':       (bRow['dsa_wins']       as num?)?.toInt() ?? 0,
            'post_count':     (bRow['post_count']     as num?)?.toInt() ?? 0,
            'max_post_likes': (bRow['max_post_likes'] as num?)?.toInt() ?? 0,
            'friend_count':   (bRow['friend_count']   as num?)?.toInt() ?? 0,
          });
          if (mounted) setState(() => _bannerRank = br);
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Friend actions ──────────────────────────────────────────────────────────
  Future<void> _sendRequest() async {
    if (_myId == null || _actionBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _actionBusy = true);
    try {
      final res = await _sb.from('friendships').insert({
        'sender_id':   _myId,
        'receiver_id': widget.userId,
        'status':      'pending',
      }).select().single();
      setState(() {
        _friendshipId = res['id']?.toString();
        _friendStatus = _FriendStatus.pendingSent;
      });
      final myName = _sb.auth.currentUser?.userMetadata?['name']?.toString() ?? 'Someone';
      NotificationService.sendFriendRequestNotification(
        toUserId: widget.userId, fromName: myName);
    } catch (e) {
      _snack('Failed to send request');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _cancelRequest() async {
    if (_friendshipId == null || _actionBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _actionBusy = true);
    try {
      await _sb.from('friendships').delete().eq('id', _friendshipId!);
      setState(() { _friendshipId = null; _friendStatus = _FriendStatus.none; });
    } catch (_) { _snack('Failed'); }
    finally { if (mounted) setState(() => _actionBusy = false); }
  }

  Future<void> _acceptRequest() async {
    if (_friendshipId == null || _actionBusy) return;
    HapticFeedback.mediumImpact();
    setState(() => _actionBusy = true);
    try {
      await _sb.from('friendships')
          .update({'status': 'accepted', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', _friendshipId!);
      _snack('🎉 You\'re now friends!', success: true);
      // Notify the original sender that their request was accepted
      final myName = _sb.auth.currentUser?.userMetadata?['name']?.toString() ?? 'Someone';
      NotificationService.sendFriendAcceptNotification(
        toUserId: widget.userId, fromName: myName);
      await _load();
    } catch (_) { _snack('Failed'); }
    finally { if (mounted) setState(() => _actionBusy = false); }
  }

  Future<void> _declineRequest() async {
    if (_friendshipId == null || _actionBusy) return;
    HapticFeedback.lightImpact();
    setState(() => _actionBusy = true);
    try {
      await _sb.from('friendships')
          .update({'status': 'declined', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', _friendshipId!);
      setState(() { _friendshipId = null; _friendStatus = _FriendStatus.none; });
    } catch (_) { _snack('Failed'); }
    finally { if (mounted) setState(() => _actionBusy = false); }
  }

  Future<void> _unfriend() async {
    if (_friendshipId == null || _actionBusy) return;
    final confirm = await _confirmDialog('Unfriend?',
        'You will no longer be friends with ${_profile?['name'] ?? 'this person'}.');
    if (!confirm) return;
    HapticFeedback.lightImpact();
    setState(() => _actionBusy = true);
    try {
      await _sb.from('friendships').delete().eq('id', _friendshipId!);
      setState(() { _friendshipId = null; _friendStatus = _FriendStatus.none; });
    } catch (_) { _snack('Failed'); }
    finally { if (mounted) setState(() => _actionBusy = false); }
  }

  Future<void> _blockUser() async {
    if (_myId == null || _actionBusy) return;
    final name = _profile?['name'] ?? 'this person';
    final confirm = await _confirmDialog('Block $name?',
        'They won\'t be able to message you or see your posts. You can unblock them later.');
    if (!confirm) return;
    setState(() => _actionBusy = true);
    try {
      await _sb.from('blocked_users').insert({
        'blocker_id': _myId,
        'blocked_id': widget.userId,
      });
      // Also remove friendship if exists
      if (_friendshipId != null) {
        await _sb.from('friendships').delete().eq('id', _friendshipId!);
      }
      setState(() {
        _isBlocked = true;
        _friendshipId = null;
        _friendStatus = _FriendStatus.none;
      });
      _snack('🚫 $name blocked', success: true);
    } catch (_) { _snack('Failed to block'); }
    finally { if (mounted) setState(() => _actionBusy = false); }
  }

  Future<void> _unblockUser() async {
    if (_myId == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _sb.from('blocked_users')
          .delete()
          .eq('blocker_id', _myId!)
          .eq('blocked_id', widget.userId);
      setState(() => _isBlocked = false);
      _snack('✅ Unblocked', success: true);
    } catch (_) { _snack('Failed to unblock'); }
    finally { if (mounted) setState(() => _actionBusy = false); }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          if (_isBlocked)
            _OptionTile(
              icon: Icons.lock_open_rounded,
              label: 'Unblock ${_profile?['name'] ?? 'user'}',
              color: const Color(0xFF4ADE80),
              onTap: () { Navigator.pop(context); _unblockUser(); },
            )
          else
            _OptionTile(
              icon: Icons.block_rounded,
              label: 'Block ${_profile?['name'] ?? 'user'}',
              color: Colors.red.shade400,
              onTap: () { Navigator.pop(context); _blockUser(); },
            ),
        ]),
      ),
    );
  }

  Future<bool> _confirmDialog(String title, String body) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(
            color: AppColors.text(context), fontWeight: FontWeight.w900)),
        content: Text(body, style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(context)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Confirm', style: TextStyle(color: AppColors.text(context)))),
        ])) ?? false;
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? const Color(0xFF4ADE80) : Colors.red.shade400,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _joinDate(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'Joined ${months[d.month - 1]} ${d.year}';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background(context),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.text(context), size: 20),
            onPressed: () => Navigator.pop(context))),
        body: Center(child: CircularProgressIndicator(
          color: _indigo, backgroundColor: _indigo.withOpacity(0.1))));
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: AppColors.background(context),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.text(context), size: 20),
            onPressed: () => Navigator.pop(context))),
        body: Center(child: Text('Profile not found',
          style: TextStyle(color: AppColors.textSecondary(context)))));
    }

    final name        = _profile!['name']?.toString() ?? 'Unknown';
    final emoji       = _profile!['avatar_emoji']?.toString().isNotEmpty == true
        ? _profile!['avatar_emoji'].toString() : '🎓';
    final bio         = _profile!['bio']?.toString() ?? '';
    final college     = _profile!['college_name']?.toString() ?? '';
    final branch      = _profile!['branch_name']?.toString()
        ?? _profile!['branch']?.toString() ?? '';
    final joinDate    = _joinDate(_profile!['created_at']?.toString());

    // ── FIX: use full 30-theme list, clamped to correct length ──
    final bannerIdx   = ((_profile!['banner_index'] as num?)?.toInt() ?? 0)
        .clamp(0, kBannerThemes.length - 1);
    final bannerColors = _themeColors(bannerIdx);

    final friendCount = (_profile!['friend_count'] as num?)?.toInt() ?? 0;
    final isVerified  = _profile!['college_status']?.toString() == 'verified';
    final isOwnProfile = _myId == widget.userId;

    final unoWins     = (_stats?['games_won']       as num?)?.toInt() ?? 0;
    final gamesPlayed = (_stats?['games_played']    as num?)?.toInt() ?? 0;
    final gamesLost   = (_stats?['games_lost']      as num?)?.toInt() ?? 0;
    final winStreak   = (_stats?['win_streak']      as num?)?.toInt() ?? 0;
    final bestStreak  = (_stats?['best_win_streak'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(slivers: [

            // ── Sliver App Bar with banner ────────────────────────────────
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: AppColors.background(context),
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle),
                    child: Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 18)))),
              actions: _myId != null && _myId != widget.userId ? [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: _showMoreOptions,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.more_vert_rounded,
                        color: Colors.white, size: 20)))),
              ] : null,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(children: [
                  // Banner — animated for special ranks, themed gradient otherwise
                  if (_bannerRank != BannerRank.none)
                    Positioned.fill(child: _AnimatedSliverBanner(rank: _bannerRank))
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: bannerColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          // 3-stop gradient if we have 3 colors
                          stops: bannerColors.length >= 3
                              ? const [0.0, 0.5, 1.0] : null))),
                  // Mesh overlay (only when no special banner)
                  if (_bannerRank == BannerRank.none)
                    Positioned.fill(child: CustomPaint(
                      painter: _MeshPainter(bannerColors.first))),
                  // Bottom fade to background
                  Positioned(
                    left: 0, right: 0, bottom: 0, height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.background(context),
                          ])))),
                  // Avatar centered at bottom of banner
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 88, height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            bannerColors.first.withOpacity(0.4),
                            bannerColors.last.withOpacity(0.2),
                          ]),
                          border: Border.all(
                            color: AppColors.background(context), width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: bannerColors.first.withOpacity(0.4),
                              blurRadius: 20, spreadRadius: 2)]),
                        child: Center(child: Text(emoji,
                          style: TextStyle(fontSize: 42)))),
                      const SizedBox(height: 8),
                    ])),
                ])),
            ),

            // ── Profile body ──────────────────────────────────────────────
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [

                  // Name + verified badge
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(child: Text(name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 24, fontWeight: FontWeight.w900,
                        letterSpacing: -0.5))),
                    if (isVerified) ...[
                      const SizedBox(width: 8),
                      _VerifiedBadge(),
                    ],
                  ]),
                  if ((_profile!['username']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('@${_profile!['username']}',
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 6),

                  // Branch + College
                  if (branch.isNotEmpty || college.isNotEmpty)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8, runSpacing: 6,
                      children: [
                        if (branch.isNotEmpty)
                          _InfoChip(emoji: '🎓', label: branch, color: _indigo),
                        if (college.isNotEmpty)
                          _InfoChip(emoji: '🏛️', label: college, color: _pink),
                      ]),
                  const SizedBox(height: 6),

                  // Join date
                  if (joinDate.isNotEmpty)
                    Text(joinDate,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12, fontWeight: FontWeight.w500)),

                  // Banner Nameplate
                  if (_bannerRank != BannerRank.none) ...[
                    const SizedBox(height: 12),
                    BannerNameplate(bannerRank: _bannerRank),
                  ],

                  // Bio
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border(context))),
                      child: Text('"$bio"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13, fontStyle: FontStyle.italic,
                          height: 1.5)))],

                  const SizedBox(height: 20),

                  // Stats row
                  _StatsRow(
                    postCount: _postCount,
                    friendCount: friendCount,
                    unoWins: unoWins,
                    winStreak: winStreak,
                    onFriendsTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => FriendsScreen(
                        userId: widget.userId,
                        displayName: _profile?['name']?.toString()))),
                  ),

                  const SizedBox(height: 20),

                  // Friend action buttons
                  if (!isOwnProfile)
                    _FriendActionButtons(
                      status: _friendStatus,
                      busy: _actionBusy,
                      onSend:     _sendRequest,
                      onCancel:   _cancelRequest,
                      onAccept:   _acceptRequest,
                      onDecline:  _declineRequest,
                      onUnfriend: _unfriend,
                      onMessage:  () => openChatWith(
                        context,
                        otherUserId: widget.userId,
                        otherName:   _profile?['name']?.toString() ?? 'Unknown',
                        otherEmoji:  _profile?['avatar_emoji']?.toString().isNotEmpty == true
                            ? _profile!['avatar_emoji'].toString() : '🎓',
                      ),
                    ),

                  if (isOwnProfile) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _indigo.withOpacity(0.25))),
                      child: Text('This is your profile',
                        style: TextStyle(
                          color: _indigo, fontSize: 12,
                          fontWeight: FontWeight.w700)))],

                  const SizedBox(height: 28),

                  // Game Stats card
                  if (gamesPlayed > 0 || unoWins > 0)
                    _GameStatsCard(
                      gamesPlayed: gamesPlayed, gamesWon: unoWins,
                      gamesLost: gamesLost, winStreak: winStreak,
                      bestStreak: bestStreak),

                  if (gamesPlayed == 0 && unoWins == 0)
                    _EmptyGameStats(name: name),

                  const SizedBox(height: 28),

                  // Posts section
                  _UserPostsSection(
                    posts: _posts, loading: _postsLoading, name: name),
                ])))
          ]))));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Friend Action Buttons
// ══════════════════════════════════════════════════════════════════════════════
class _FriendActionButtons extends StatelessWidget {
  final _FriendStatus status;
  final bool busy;
  final VoidCallback onSend, onCancel, onAccept, onDecline, onUnfriend;
  final VoidCallback? onMessage;

  const _FriendActionButtons({
    required this.status, required this.busy,
    required this.onSend, required this.onCancel,
    required this.onAccept, required this.onDecline,
    required this.onUnfriend, this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _FriendStatus.none:
        return _GradBtn(
          label: 'Add Friend', icon: Icons.person_add_rounded,
          gradient: const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFFE879F9)]),
          onTap: busy ? null : onSend, busy: busy);

      case _FriendStatus.pendingSent:
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _OutlineBtn(label: 'Request Sent', icon: Icons.check_rounded,
            color: _indigo, onTap: null),
          const SizedBox(width: 10),
          _OutlineBtn(label: 'Cancel', icon: Icons.close_rounded,
            color: Colors.red.shade400, onTap: busy ? null : onCancel),
        ]);

      case _FriendStatus.pendingReceived:
        return Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _amber.withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('👋', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('Sent you a friend request',
                style: TextStyle(color: _amber, fontSize: 13, fontWeight: FontWeight.w700)),
            ])),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _GradBtn(
              label: 'Accept', icon: Icons.check_rounded,
              gradient: LinearGradient(colors: [_green, const Color(0xFF22C55E)]),
              onTap: busy ? null : onAccept, busy: busy),
            const SizedBox(width: 10),
            _OutlineBtn(label: 'Decline', icon: Icons.close_rounded,
              color: Colors.red.shade400, onTap: busy ? null : onDecline),
          ])]);

      case _FriendStatus.friends:
        return Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _green.withOpacity(0.35))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_rounded, color: _green, size: 18),
                const SizedBox(width: 8),
                Text('Friends', style: TextStyle(
                  color: _green, fontSize: 14, fontWeight: FontWeight.w800)),
              ])),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onUnfriend,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.surface(context), borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border(context))),
                child: Icon(Icons.person_remove_rounded,
                  color: AppColors.textSecondary(context), size: 18))),
          ]),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onMessage,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF818CF8), Color(0xFF6C63FF)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF818CF8).withOpacity(0.3),
                  blurRadius: 12, offset: const Offset(0, 4))]),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.chat_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Send Message', style: TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              ]))),
        ]);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Stats Row
// ══════════════════════════════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  final int postCount, friendCount, unoWins, winStreak;
  final VoidCallback? onFriendsTap;
  const _StatsRow({required this.postCount, required this.friendCount,
      required this.unoWins, required this.winStreak, this.onFriendsTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 16, offset: const Offset(0, 4))]),
      child: Row(children: [
        Expanded(child: _StatItem(value: '$postCount',   label: 'Posts',   emoji: '📝', color: _indigo)),
        _Divider(),
        Expanded(child: GestureDetector(
          onTap: onFriendsTap,
          child: _StatItem(value: '$friendCount', label: 'Friends', emoji: '👥',
            color: _pink, tappable: onFriendsTap != null))),
        _Divider(),
        Expanded(child: _StatItem(value: '$unoWins',     label: 'Wins',    emoji: '🏆', color: _amber)),
        _Divider(),
        Expanded(child: _StatItem(value: '$winStreak',   label: 'Streak',  emoji: '🔥', color: _green)),
      ]));
  }
}

class _StatItem extends StatelessWidget {
  final String value, label, emoji;
  final Color color;
  final bool tappable;
  const _StatItem({required this.value, required this.label,
      required this.emoji, required this.color, this.tappable = false});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(emoji, style: TextStyle(fontSize: 20)),
    const SizedBox(height: 4),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(value, style: TextStyle(
        color: color, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      if (tappable) ...[
        const SizedBox(width: 3),
        Icon(Icons.arrow_forward_ios_rounded, color: color, size: 10),
      ],
    ]),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 10, fontWeight: FontWeight.w600)),
  ]);
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 40, color: AppColors.border(context));
}

// ══════════════════════════════════════════════════════════════════════════════
// Game Stats Card
// ══════════════════════════════════════════════════════════════════════════════
class _GameStatsCard extends StatelessWidget {
  final int gamesPlayed, gamesWon, gamesLost, winStreak, bestStreak;
  const _GameStatsCard({required this.gamesPlayed, required this.gamesWon,
      required this.gamesLost, required this.winStreak, required this.bestStreak});

  @override
  Widget build(BuildContext context) {
    final winRate = gamesPlayed > 0
        ? ((gamesWon / gamesPlayed) * 100).round() : 0;

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 16, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _amber.withOpacity(0.2), _pink.withOpacity(0.2)]),
              borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text('🎮', style: TextStyle(fontSize: 18)))),
          const SizedBox(width: 10),
          Text('Game Stats', style: TextStyle(
            color: AppColors.text(context), fontSize: 16,
            fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          const Spacer(),
          if (winStreak > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFBBF24), Color(0xFFF97316)]),
                borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('🔥', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Text('$winStreak streak', style: TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ])),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Text('Win Rate', style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$winRate%', style: TextStyle(
            color: _green, fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: winRate / 100,
            backgroundColor: AppColors.border(context),
            valueColor: AlwaysStoppedAnimation(
              winRate >= 60 ? _green : winRate >= 40 ? _amber : Colors.red.shade400),
            minHeight: 8)),
        const SizedBox(height: 16),
        Row(children: [
          _GameTile(game: 'Wins',   emoji: '🏆', wins: gamesWon,  color: _green),
          const SizedBox(width: 12),
          _GameTile(game: 'Losses', emoji: '💀', wins: gamesLost, color: const Color(0xFFEF4444)),
        ]),
      ]));
  }
}

class _GameTile extends StatelessWidget {
  final String game, emoji; final int wins; final Color color;
  const _GameTile({required this.game, required this.emoji,
      required this.wins, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.2))),
    child: Row(children: [
      Text(emoji, style: TextStyle(fontSize: 22)),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(game, style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 10, fontWeight: FontWeight.w700)),
        Text('$wins', style: TextStyle(
          color: color, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
      ]),
    ])));
}

class _EmptyGameStats extends StatelessWidget {
  final String name;
  const _EmptyGameStats({required this.name});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.surface(context), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border(context))),
    child: Column(children: [
      Text('🎮', style: TextStyle(fontSize: 36)),
      const SizedBox(height: 10),
      Text('No games played yet', style: TextStyle(
        color: AppColors.text(context), fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Challenge ${name.split(' ').first} to a game!',
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
    ]));
}

// ══════════════════════════════════════════════════════════════════════════════
// Small reusable widgets
// ══════════════════════════════════════════════════════════════════════════════
class _InfoChip extends StatelessWidget {
  final String emoji, label; final Color color;
  const _InfoChip({required this.emoji, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: TextStyle(fontSize: 12)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(
        color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]));
}

class _VerifiedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFFE879F9)]),
      borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: const [
      Icon(Icons.verified_rounded, color: Colors.white, size: 12),
      SizedBox(width: 3),
      Text('Verified', style: TextStyle(
        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
    ]));
}

class _GradBtn extends StatelessWidget {
  final String label; final IconData icon;
  final LinearGradient gradient; final VoidCallback? onTap; final bool busy;
  const _GradBtn({required this.label, required this.icon,
      required this.gradient, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
      decoration: BoxDecoration(
        gradient: onTap == null ? null : gradient,
        color: onTap == null ? AppColors.border(context) : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: onTap == null ? null : [BoxShadow(
          color: const Color(0xFF818CF8).withOpacity(0.35),
          blurRadius: 14, offset: const Offset(0, 5))]),
      child: busy
        ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          ])));
}

class _OutlineBtn extends StatelessWidget {
  final String label; final IconData icon;
  final Color color; final VoidCallback? onTap;
  const _OutlineBtn({required this.label, required this.icon,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ])));
}

// ══════════════════════════════════════════════════════════════════════════════
// Mesh painter for banner atmosphere
// ══════════════════════════════════════════════════════════════════════════════
class _MeshPainter extends CustomPainter {
  final Color color;
  _MeshPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.06)..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.3, size.height * 0.1,
        size.width * 0.6, size.height * 0.5);
    path.quadraticBezierTo(size.width * 0.8, size.height * 0.8,
        size.width, size.height * 0.3);
    path.lineTo(size.width, 0);
    path.lineTo(0, 0);
    path.close();
    canvas.drawPath(path, paint);

    final paint2 = Paint()..color = Colors.black.withOpacity(0.08)..style = PaintingStyle.fill;
    final path2 = Path();
    path2.moveTo(size.width, size.height * 0.6);
    path2.quadraticBezierTo(size.width * 0.7, size.height * 0.3,
        size.width * 0.4, size.height * 0.7);
    path2.quadraticBezierTo(size.width * 0.2, size.height,
        0, size.height * 0.8);
    path2.lineTo(0, size.height);
    path2.lineTo(size.width, size.height);
    path2.close();
    canvas.drawPath(path2, paint2);
  }

  @override bool shouldRepaint(_MeshPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════════════════════
// Animated banner for special BannerRank users
// ══════════════════════════════════════════════════════════════════════════════
class _AnimatedSliverBanner extends StatefulWidget {
  final BannerRank rank;
  const _AnimatedSliverBanner({required this.rank});

  @override
  State<_AnimatedSliverBanner> createState() => _AnimatedSliverBannerState();
}

class _AnimatedSliverBannerState extends State<_AnimatedSliverBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final meta = kBanners[widget.rank]!;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _SliverBannerPainter(meta: meta, t: _ctrl.value)));
  }
}

class _SliverBannerPainter extends CustomPainter {
  final BannerMeta meta; final double t;
  _SliverBannerPainter({required this.meta, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    p.shader = LinearGradient(
      colors: [meta.secondary, meta.primary, meta.secondary],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);

    final ox = size.width * (0.15 + 0.7 * (0.5 + 0.5 * math.sin(t * math.pi * 2)));
    p.shader = RadialGradient(
      colors: [meta.primary.withOpacity(0.45), Colors.transparent],
    ).createShader(Rect.fromCircle(center: Offset(ox, size.height * 0.4), radius: 90));
    canvas.drawCircle(Offset(ox, size.height * 0.4), 90, p);

    final sx = -size.width * 0.3 + t * size.width * 1.6;
    p.shader = LinearGradient(
      colors: [Colors.transparent, Colors.white.withOpacity(0.14), Colors.transparent],
      stops: const [0, 0.5, 1],
    ).createShader(Rect.fromLTWH(sx - 30, 0, 60, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p);
  }

  @override bool shouldRepaint(_SliverBannerPainter o) => o.t != t;
}

// ══════════════════════════════════════════════════════════════════════════════
// User Posts Section
// ══════════════════════════════════════════════════════════════════════════════
class _UserPostsSection extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final bool loading;
  final String name;
  const _UserPostsSection({required this.posts, required this.loading, required this.name});

  @override
  State<_UserPostsSection> createState() => _UserPostsSectionState();
}

class _UserPostsSectionState extends State<_UserPostsSection>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Set<String> _likedPostIds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _fetchMyLikes();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondary(context);
    final surface       = AppColors.surface(context);
    final border        = AppColors.border(context);

    final imagePosts = widget.posts.where((p) =>
        (p['image_url'] as String?)?.isNotEmpty == true).toList();
    final textPosts  = widget.posts.where((p) =>
        (p['image_url'] as String?)?.isEmpty != false).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      Container(
        decoration: BoxDecoration(
          color: AppColors.background(context),
          border: Border(top: BorderSide(color: border), bottom: BorderSide(color: border))),
        child: TabBar(
          controller: _tab,
          indicatorColor: _indigo, indicatorWeight: 2,
          labelColor: _indigo, unselectedLabelColor: textSecondary,
          tabs: [
            Tab(icon: Icon(Icons.grid_on_rounded, size: 22,
              color: _tab.index == 0 ? _indigo : textSecondary)),
            Tab(icon: Icon(Icons.format_align_left_rounded, size: 22,
              color: _tab.index == 1 ? _indigo : textSecondary)),
          ],
        )),

      const SizedBox(height: 2),

      if (widget.loading)
        Padding(padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _indigo)))

      else if (widget.posts.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('📭', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text('No public posts yet', style: TextStyle(
              color: textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
          ])))

      else ...[
        if (_tab.index == 0)
          imagePosts.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('🖼️', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text('No photo posts yet', style: TextStyle(color: textSecondary, fontSize: 13)),
                ])))
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 2,
                  mainAxisSpacing: 2, childAspectRatio: 1),
                itemCount: imagePosts.length,
                itemBuilder: (context, i) {
                  final post     = imagePosts[i];
                  final imageUrl = post['image_url'] as String? ?? '';
                  final likes    = (post['likes'] as num?)?.toInt() ?? 0;
                  return GestureDetector(
                    onTap: () => _showPostDetail(context, post),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network(imageUrl, fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                          progress == null ? child : Container(color: surface),
                        errorBuilder: (_, __, ___) => Container(
                          color: surface,
                          child: Icon(Icons.broken_image_rounded,
                            color: Colors.white24, size: 28))),
                      Positioned(bottom: 4, left: 4,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.favorite_rounded, size: 11, color: AppColors.textSecondary(context)),
                          const SizedBox(width: 2),
                          Text('$likes', style: TextStyle(
                            color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                        ])),
                    ]));
                })

        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8),
            itemCount: textPosts.isEmpty ? 1 : textPosts.length,
            separatorBuilder: (_, __) => Divider(color: border, height: 1),
            itemBuilder: (context, i) {
              if (textPosts.isEmpty) {
                return Padding(padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('No text posts yet',
                    style: TextStyle(color: textSecondary, fontSize: 13))));
              }
              final post     = textPosts[i];
              final content  = post['content']?.toString() ?? '';
              final likes    = (post['likes'] as num?)?.toInt() ?? 0;
              final comments = (post['comment_count'] as num?)?.toInt() ?? 0;
              final timeAgo  = _formatTime(post['created_at']?.toString() ?? '');
              return GestureDetector(
                onTap: () => _showPostDetail(context, post),
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(content, style: TextStyle(
                      color: AppColors.text(context), fontSize: 14, height: 1.55),
                      maxLines: 5, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(timeAgo, style: TextStyle(color: textSecondary, fontSize: 11)),
                      const Spacer(),
                      Icon(Icons.favorite_rounded, size: 13, color: _pink.withOpacity(0.8)),
                      const SizedBox(width: 3),
                      Text('$likes', style: TextStyle(
                        color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Icon(Icons.chat_bubble_outline_rounded, size: 13,
                        color: _indigo.withOpacity(0.8)),
                      const SizedBox(width: 3),
                      Text('$comments', style: TextStyle(
                        color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ])));
            }),
      ],

      const SizedBox(height: 24),
    ]);
  }

  Future<void> _fetchMyLikes() async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final data = await _sb.from('buzz_likes').select('post_id').eq('user_id', myId);
      if (mounted) setState(() => _likedPostIds = Set<String>.from(
          (data as List).map((r) => r['post_id'].toString())));
    } catch (_) {}
  }

  Future<void> _toggleLike(String postId, int currentLikes) async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    final alreadyLiked = _likedPostIds.contains(postId);
    HapticFeedback.lightImpact();
    setState(() {
      if (alreadyLiked) { _likedPostIds.remove(postId); } else { _likedPostIds.add(postId); }
    });
    try {
      if (alreadyLiked) {
        await _sb.from('buzz_likes').delete().eq('user_id', myId).eq('post_id', postId);
        await _sb.from('buzz_posts').update({'likes': currentLikes - 1}).eq('id', postId);
      } else {
        await _sb.from('buzz_likes').insert({'user_id': myId, 'post_id': postId});
        await _sb.from('buzz_posts').update({'likes': currentLikes + 1}).eq('id', postId);
      }
    } catch (_) {
      if (mounted) setState(() {
        if (alreadyLiked) { _likedPostIds.add(postId); } else { _likedPostIds.remove(postId); }
      });
    }
  }

  void _showPostDetail(BuildContext context, Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent, enableDrag: true,
      builder: (_) => _PostDetailSheet(
        post: post,
        isLiked: _likedPostIds.contains(post['id']?.toString() ?? ''),
        onLike: () => _toggleLike(
          post['id'].toString(), (post['likes'] as num?)?.toInt() ?? 0),
        onCommentCountChanged: (_) {}));
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt  = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1)  return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)   return '${diff.inHours}h ago';
      if (diff.inDays < 7)     return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Post Detail Bottom Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _PostDetailSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isLiked;
  final VoidCallback onLike;
  final void Function(int delta) onCommentCountChanged;

  const _PostDetailSheet({required this.post, required this.isLiked,
      required this.onLike, required this.onCommentCountChanged});

  @override
  State<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends State<_PostDetailSheet> {
  late bool _liked;
  late int  _likes;
  late int  _comments;

  @override
  void initState() {
    super.initState();
    _liked    = widget.isLiked;
    _likes    = (widget.post['likes'] as num?)?.toInt() ?? 0;
    _comments = (widget.post['comment_count'] as num?)?.toInt() ?? 0;
  }

  void _handleLike() {
    widget.onLike();
    setState(() { _liked = !_liked; _likes += _liked ? 1 : -1; });
  }

  void _handleComment() async {
    final postId      = widget.post['id']?.toString() ?? '';
    final postOwnerId = widget.post['user_id']?.toString() ?? '';
    final content     = widget.post['content']?.toString() ?? '';
    final before      = _comments;
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        postId: postId, postOwnerId: postOwnerId,
        isAnonymousPost: false, postContent: content));
    try {
      final row = await _sb.from('buzz_posts')
          .select('comment_count').eq('id', postId).single();
      final fresh = (row['comment_count'] as num?)?.toInt() ?? before;
      if (mounted) {
        final delta = fresh - before;
        setState(() => _comments = fresh);
        if (delta != 0) widget.onCommentCountChanged(delta);
      }
    } catch (_) {}
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final now  = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1)  return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)   return '${diff.inHours}h ago';
      if (diff.inDays < 7)     return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final textColor     = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surface       = AppColors.surface(context);
    final border        = AppColors.border(context);
    final imageUrl = widget.post['image_url'] as String? ?? '';
    final content  = widget.post['content']?.toString() ?? '';
    final timeAgo  = _formatTime(widget.post['created_at']?.toString() ?? '');

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: DraggableScrollableSheet(
        initialChildSize: 0.72, maxChildSize: 0.95, minChildSize: 0.35,
        builder: (_, scrollCtrl) => GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Expanded(child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (imageUrl.isNotEmpty) ...[
                    GestureDetector(
                      onTap: () => _showFullImage(context, imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(imageUrl, width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
                    const SizedBox(height: 14),
                  ],
                  if (content.isNotEmpty)
                    Text(content, style: TextStyle(
                      color: textColor, fontSize: 15, height: 1.6)),
                  const SizedBox(height: 16),
                  Divider(color: border),
                  const SizedBox(height: 8),
                  Row(children: [
                    GestureDetector(
                      onTap: _handleLike,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _liked ? _pink.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _liked ? _pink.withOpacity(0.4) : border)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 18, color: _liked ? _pink : textSecondary),
                          const SizedBox(width: 6),
                          Text('$_likes', style: TextStyle(
                            color: _liked ? _pink : textSecondary,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                        ]))),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _handleComment,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                            size: 18, color: textSecondary),
                          const SizedBox(width: 6),
                          Text('$_comments', style: TextStyle(
                            color: textSecondary, fontSize: 14, fontWeight: FontWeight.w700)),
                        ]))),
                    const Spacer(),
                    Text(timeAgo, style: TextStyle(color: textSecondary, fontSize: 12)),
                  ]),
                ]))),
            ])))));
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.push(context, PageRouteBuilder(
      opaque: false, barrierColor: Colors.black87, barrierDismissible: true,
      pageBuilder: (_, __, ___) => GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: GestureDetector(
            onTap: () {},
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image_rounded, color: Colors.white38, size: 64))))))),
      transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child)));
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.label,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Text(label, style: TextStyle(
            color: color, fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
