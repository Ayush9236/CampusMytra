import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';
import 'user_profile_screen.dart';

final _sbF = Supabase.instance.client;

void openFriendsScreen(BuildContext context, String userId, {String? displayName}) {
  Navigator.push(context, MaterialPageRoute(
      builder: (_) => FriendsScreen(userId: userId, displayName: displayName)));
}

class FriendsScreen extends StatefulWidget {
  final String userId;
  final String? displayName;
  const FriendsScreen({super.key, required this.userId, this.displayName});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _friends  = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  late final AnimationController _animCtrl;
  final String? _myId = _sbF.auth.currentUser?.id;

  static const _indigo = Color(0xFF818CF8);
  static const _pink   = Color(0xFFE879F9);
  static const _green  = Color(0xFF4ADE80);

  bool get _isOwnProfile => _myId == widget.userId;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _load();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Single RPC — joins friendships + profiles in one DB round-trip
      final rows = await _sbF.rpc('get_friends',
          params: {'target_user_id': widget.userId});

      final enriched = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      // already sorted by name from RPC

      if (mounted) setState(() { _friends = enriched; _filtered = enriched; _loading = false; });
      _animCtrl.forward(from: 0);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    setState(() {
      _filtered = q.isEmpty ? _friends : _friends.where((f) {
        final name    = (f['username'] ?? f['name'])?.toString().toLowerCase() ?? '';
        final college = f['college_name']?.toString().toLowerCase() ?? '';
        final branch  = (f['branch_name'] ?? f['branch'])?.toString().toLowerCase() ?? '';
        return name.contains(q.toLowerCase()) || college.contains(q.toLowerCase()) || branch.contains(q.toLowerCase());
      }).toList();
    });
  }

  Future<void> _unfriend(String friendshipId, String friendName, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Friend?',
            style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.w900)),
        content: Text('Remove $friendName from your friends?',
            style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary(context)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ]));
    if (confirmed != true) return;
    HapticFeedback.lightImpact();
    try {
      await _sbF.from('friendships').delete().eq('id', friendshipId);
      if (mounted) {
        setState(() {
          _friends.removeWhere((f) => f['friendship_id'] == friendshipId);
          _filtered.removeAt(index);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Removed $friendName'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bgColor    = AppColors.background(context);
    final textColor  = AppColors.text(context);
    final subColor   = AppColors.textSecondary(context);
    final surfaceCol = AppColors.surface(context);
    final borderCol  = AppColors.border(context);
    final title      = _isOwnProfile ? 'My Friends' : (widget.displayName ?? 'Their') + ' Friends';

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(slivers: [

        SliverAppBar(
          pinned: true,
          expandedHeight: 130,
          backgroundColor: AppColors.background(context),
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
            onPressed: () => Navigator.pop(context)),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            title: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                      colors: [_indigo, _pink]).createShader(b),
                  child: Text(title, style: const TextStyle(
                      color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.w900, letterSpacing: -0.5))),
                if (!_loading)
                  Text('${_friends.length} ${_friends.length == 1 ? 'friend' : 'friends'}',
                    style: TextStyle(color: subColor, fontSize: 11)),
              ])),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(color: borderCol, height: 1))),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: surfaceCol,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol)),
              child: TextField(
                onChanged: _onSearch,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search friends...',
                  hintStyle: TextStyle(color: subColor, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: subColor, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))))),

        if (_loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: _indigo, strokeWidth: 2)))
        else if (_filtered.isEmpty)
          SliverFillRemaining(
            child: Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      _indigo.withOpacity(0.15), _pink.withOpacity(0.15)]),
                    borderRadius: BorderRadius.circular(24)),
                  child: const Center(child: Text('👥', style: TextStyle(fontSize: 36)))),
                const SizedBox(height: 16),
                Text(_isOwnProfile ? 'No friends yet' : 'No friends to show',
                  style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_isOwnProfile
                  ? 'Start connecting with people on campus!'
                  : 'This user hasnt connected with anyone yet',
                  style: TextStyle(color: subColor, fontSize: 13),
                  textAlign: TextAlign.center),
              ]))))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final f          = _filtered[i];
                  final name       = (f['username'] ?? f['name'])?.toString() ?? 'Unknown';
                  final emoji      = f['avatar_emoji']?.toString().isNotEmpty == true
                      ? f['avatar_emoji'].toString() : '🎓';
                  final branch     = (f['branch_name'] ?? f['branch'])?.toString() ?? '';
                  final college    = f['college_name']?.toString() ?? '';
                  final isVerified = f['college_status']?.toString() == 'verified';
                  final friendId   = f['friend_id']?.toString() ?? '';
                  final fshipId    = f['friendship_id']?.toString() ?? '';

                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _animCtrl,
                      curve: Interval(
                        (i / (_filtered.length + 1)).clamp(0.0, 0.8),
                        ((i + 1) / (_filtered.length + 1)).clamp(0.2, 1.0),
                        curve: Curves.easeOut)),
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => UserProfileScreen(userId: friendId))),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: surfaceCol,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderCol),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12, offset: const Offset(0, 3))]),
                        child: Row(children: [
                          // Avatar
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(colors: [
                                _indigo.withOpacity(0.3), Colors.transparent]),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _indigo.withOpacity(0.35), width: 1.5)),
                            child: Center(child: Text(emoji,
                                style: const TextStyle(fontSize: 24)))),
                          const SizedBox(width: 14),
                          // Info
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Flexible(child: Text(name,
                                  style: TextStyle(color: textColor,
                                    fontSize: 15, fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis)),
                                if (isVerified) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _green.withOpacity(0.4))),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.verified_rounded, color: _green, size: 10),
                                      const SizedBox(width: 3),
                                      Text('Verified', style: TextStyle(
                                        color: _green, fontSize: 9,
                                        fontWeight: FontWeight.w800)),
                                    ])),
                                ],
                              ]),
                              const SizedBox(height: 3),
                              if (branch.isNotEmpty || college.isNotEmpty)
                                Text(
                                  [if (branch.isNotEmpty) branch,
                                   if (college.isNotEmpty) college].join(' • '),
                                  style: TextStyle(color: subColor, fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            ])),
                          const SizedBox(width: 10),
                          // Actions
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: _indigo.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _indigo.withOpacity(0.2))),
                              child: const Icon(Icons.arrow_forward_ios_rounded,
                                  color: _indigo, size: 14)),
                            if (_isOwnProfile) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _unfriend(fshipId, name, i),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.red.withOpacity(0.25))),
                                  child: Icon(Icons.person_remove_rounded,
                                      color: Colors.red.shade400, size: 16))),
                            ],
                          ]),
                        ]))));
                },
                childCount: _filtered.length))),
      ]));
  }
}