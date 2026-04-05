import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';
import '../profile/user_profile_screen.dart';
import '../badges/badge_system.dart';

final _sbSearch = Supabase.instance.client;

// ══════════════════════════════════════════════════════════
// Entry point
// ══════════════════════════════════════════════════════════
void openSearchScreen(BuildContext context) {
  Navigator.push(context,
    PageRouteBuilder(
      pageBuilder: (_, anim, __) => const SearchScreen(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 250),
    ));
}

// ══════════════════════════════════════════════════════════
// SearchScreen
// ══════════════════════════════════════════════════════════
class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchTab { people, posts }

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {

  final _ctrl    = TextEditingController();
  final _focus   = FocusNode();
  Timer?  _debounce;
  String  _query = '';
  bool    _searching = false;
  _SearchTab _tab = _SearchTab.people;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _recentSearches = [];

  // For stagger animation
  late AnimationController _listAnim;

  // colour palette — matches app style
  static const _indigo = Color(0xFF818CF8);
  static const _pink   = Color(0xFFE879F9);
  static const _green  = Color(0xFF4ADE80);
  static const _amber  = Color(0xFFFBBF24);
  static const _teal   = Color(0xFF00B8A3);

  @override
  void initState() {
    super.initState();
    _listAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _ctrl.addListener(_onType);
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onType);
    _ctrl.dispose();
    _focus.dispose();
    _listAnim.dispose();
    super.dispose();
  }

  void _onType() {
    final q = _ctrl.text.trim();
    if (q == _query) return;
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() { _users = []; _posts = []; _searching = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      await Future.wait([
        if (_tab == _SearchTab.people) _searchUsers(q),
        if (_tab == _SearchTab.posts)  _searchPosts(q),
      ]);
    } finally {
      if (mounted) {
        setState(() => _searching = false);
        _listAnim.forward(from: 0);
      }
    }
  }

  Future<void> _searchUsers(String q) async {
    try {
      final data = await _sbSearch
          .from('profiles')
          .select('id, name, avatar_emoji, banner_index, college_name, branch_name, branch, college_status, friend_count')
          .or('name.ilike.%$q%,college_name.ilike.%$q%,branch_name.ilike.%$q%')
          .limit(20);
      if (mounted) setState(() => _users = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  Future<void> _searchPosts(String q) async {
    try {
      final data = await _sbSearch
          .from('buzz_feed')
          .select()
          .eq('visibility', 'public')
          .ilike('content', '%$q%')
          .order('likes', ascending: false)
          .limit(20);
      if (mounted) setState(() => _posts = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  // ── Recent searches stored locally in state (session only) ──
  void _loadRecentSearches() {
    // kept in memory only — no persistence needed
    _recentSearches = [];
  }

  void _saveSearch(String q) {
    if (q.isEmpty) return;
    setState(() {
      _recentSearches.removeWhere((r) => r['q'] == q);
      _recentSearches.insert(0, {'q': q});
      if (_recentSearches.length > 8) _recentSearches = _recentSearches.take(8).toList();
    });
  }

  void _applyRecent(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    _search(q);
  }

  void _onTabSwitch(_SearchTab t) {
    if (_tab == t) return;
    HapticFeedback.lightImpact();
    setState(() { _tab = t; _users = []; _posts = []; });
    if (_query.isNotEmpty) _search(_query);
  }

  void _openProfile(String userId, String name) {
    _saveSearch(name);
    openUserProfile(context, userId);
  }

  // ══════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark    = AppColors.isDark(context);
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final surface   = AppColors.surface(context);
    final border    = AppColors.border(context);
    final bg        = AppColors.background(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(children: [

          // ── TOP BAR ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border)),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                    color: textColor, size: 18))),
              const SizedBox(width: 12),

              // Search field
              Expanded(child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _query.isNotEmpty
                      ? _indigo.withOpacity(0.5)
                      : border,
                    width: _query.isNotEmpty ? 1.5 : 1),
                  boxShadow: _query.isNotEmpty ? [
                    BoxShadow(
                      color: _indigo.withOpacity(0.12),
                      blurRadius: 12, offset: const Offset(0, 3))
                  ] : null),
                child: Row(children: [
                  const SizedBox(width: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _searching
                      ? SizedBox(width: 18, height: 18,
                          key: const ValueKey('loading'),
                          child: CircularProgressIndicator(
                            color: _indigo, strokeWidth: 2))
                      : Icon(Icons.search_rounded,
                          key: const ValueKey('icon'),
                          color: _query.isNotEmpty ? _indigo : subColor,
                          size: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Search people, posts...',
                      hintStyle: TextStyle(
                        color: subColor, fontSize: 14,
                        fontWeight: FontWeight.w400),
                      border: InputBorder.none,
                      isDense: true),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        _saveSearch(v.trim());
                        _search(v.trim());
                      }
                    },
                  )),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _ctrl.clear();
                        setState(() { _users = []; _posts = []; });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          width: 18, height: 18,
                          decoration: BoxDecoration(
                            color: subColor.withOpacity(0.2),
                            shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                            color: subColor, size: 12)))),
                  const SizedBox(width: 4),
                ]))),
            ])),

          const SizedBox(height: 14),

          // ── TABS ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border)),
              child: Row(children: [
                Expanded(child: _TabBtn(
                  label: '👤 People',
                  selected: _tab == _SearchTab.people,
                  onTap: () => _onTabSwitch(_SearchTab.people))),
                Expanded(child: _TabBtn(
                  label: '📝 Posts',
                  selected: _tab == _SearchTab.posts,
                  onTap: () => _onTabSwitch(_SearchTab.posts))),
              ]))),

          const SizedBox(height: 12),

          // ── BODY ─────────────────────────────────────────
          Expanded(child: _buildBody(isDark, textColor, subColor, surface, border)),
        ]),
      ),
    );
  }

  Widget _buildBody(bool isDark, Color textColor, Color subColor,
      Color surface, Color border) {

    // Empty state — no query
    if (_query.isEmpty) {
      return _buildEmptyState(textColor, subColor, surface, border);
    }

    // Searching
    if (_searching) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: _indigo,
            backgroundColor: _indigo.withOpacity(0.1),
            strokeWidth: 2),
          const SizedBox(height: 16),
          Text('Searching for "$_query"...',
            style: TextStyle(color: subColor, fontSize: 13)),
        ]));
    }

    // Results
    final results = _tab == _SearchTab.people ? _users : _posts;
    if (results.isEmpty) {
      return _buildNoResults(textColor, subColor);
    }

    return _tab == _SearchTab.people
      ? _buildPeopleList(textColor, subColor, surface, border)
      : _buildPostsList(textColor, subColor, surface, border);
  }

  // ── Empty / Recent searches ──────────────────────────────
  Widget _buildEmptyState(Color textColor, Color subColor,
      Color surface, Color border) {

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        if (_recentSearches.isNotEmpty) ...[
          _SectionHeader(
            title: 'Recent',
            trailing: GestureDetector(
              onTap: () => setState(() => _recentSearches = []),
              child: Text('Clear all',
                style: TextStyle(color: _indigo, fontSize: 12,
                  fontWeight: FontWeight.w700))),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _recentSearches.map((r) {
              final q = r['q'].toString();
              return GestureDetector(
                onTap: () => _applyRecent(q),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_rounded,
                      color: subColor, size: 14),
                    const SizedBox(width: 6),
                    Text(q, style: TextStyle(
                      color: textColor, fontSize: 13,
                      fontWeight: FontWeight.w600)),
                  ])));
            }).toList()),
          const SizedBox(height: 28),
        ],

        // Hint cards
        _SectionHeader(title: 'Discover'),
        const SizedBox(height: 12),
        _HintCard(
          emoji: '👤',
          title: 'Find People',
          subtitle: 'Search by name, college, or branch',
          color: _indigo),
        const SizedBox(height: 10),
        _HintCard(
          emoji: '📝',
          title: 'Search Posts',
          subtitle: 'Find public buzz posts by keyword',
          color: _pink),
        const SizedBox(height: 10),
        _HintCard(
          emoji: '🏛️',
          title: 'Find Your College',
          subtitle: 'Search users from your institution',
          color: _teal),
      ]));
  }

  // ── No results ───────────────────────────────────────────
  Widget _buildNoResults(Color textColor, Color subColor) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _indigo.withOpacity(0.15),
              _pink.withOpacity(0.15)]),
            borderRadius: BorderRadius.circular(24)),
          child: Center(child: Text(
            _tab == _SearchTab.people ? '🔍' : '📭',
            style: const TextStyle(fontSize: 36)))),
        const SizedBox(height: 16),
        Text('No results for "$_query"',
          style: TextStyle(
            color: textColor, fontSize: 16,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          _tab == _SearchTab.people
            ? 'Try a different name or college'
            : 'Try different keywords',
          style: TextStyle(color: subColor, fontSize: 13),
          textAlign: TextAlign.center),
      ])));
  }

  // ── People list ──────────────────────────────────────────
  Widget _buildPeopleList(Color textColor, Color subColor,
      Color surface, Color border) {

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i];
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: _listAnim,
            curve: Interval(
              (i / (_users.length + 1)).clamp(0.0, 0.8),
              ((i + 1) / (_users.length + 1)).clamp(0.1, 1.0),
              curve: Curves.easeOut)),
          child: _UserCard(
            user: u,
            query: _query,
            onTap: () => _openProfile(
              u['id'].toString(),
              (u['username'] ?? u['name'])?.toString() ?? ''),
          ));
      });
  }

  // ── Posts list ───────────────────────────────────────────
  Widget _buildPostsList(Color textColor, Color subColor,
      Color surface, Color border) {

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: _posts.length,
      itemBuilder: (_, i) {
        final p = _posts[i];
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: _listAnim,
            curve: Interval(
              (i / (_posts.length + 1)).clamp(0.0, 0.8),
              ((i + 1) / (_posts.length + 1)).clamp(0.1, 1.0),
              curve: Curves.easeOut)),
          child: _PostCard(
            post: p,
            query: _query,
            onProfileTap: (uid) => openUserProfile(context, uid),
          ));
      });
  }
}

// ══════════════════════════════════════════════════════════
// User result card
// ══════════════════════════════════════════════════════════
class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final String query;
  final VoidCallback onTap;

  const _UserCard({
    required this.user,
    required this.query,
    required this.onTap,
  });

  static const _indigo = Color(0xFF818CF8);
  static const _pink   = Color(0xFFE879F9);
  static const _green  = Color(0xFF4ADE80);

  @override
  Widget build(BuildContext context) {
    final name        = (user['username'] ?? user['name'])?.toString() ?? 'Unknown';
    final emoji       = user['avatar_emoji']?.toString().isNotEmpty == true
        ? user['avatar_emoji'].toString() : '🎓';
    final college     = user['college_name']?.toString() ?? '';
    final branch      = (user['branch_name'] ?? user['branch'])?.toString() ?? '';
    final isVerified  = user['college_status']?.toString() == 'verified';
    final friendCount = (user['friend_count'] as num?)?.toInt() ?? 0;
    final bannerIdx   = ((user['banner_index'] as num?)?.toInt() ?? 0)
        .clamp(0, 7);

    // Banner gradient colours (matches app)
    const gradients = [
      [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
      [Color(0xFF00B8A3), Color(0xFF00897B)],
      [Color(0xFFFF375F), Color(0xFFE91E63)],
      [Color(0xFFFFB800), Color(0xFFF57C00)],
      [Color(0xFF1A237E), Color(0xFF283593)],
      [Color(0xFF2E7D32), Color(0xFF388E3C)],
      [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      [Color(0xFF880E4F), Color(0xFFAD1457)],
    ];
    final avatarColor = gradients[bannerIdx][0];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border(context)),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10, offset: const Offset(0, 3))]),
        child: Row(children: [

          // Avatar
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                avatarColor.withOpacity(0.35),
                avatarColor.withOpacity(0.1)]),
              shape: BoxShape.circle,
              border: Border.all(
                color: avatarColor.withOpacity(0.4), width: 1.5)),
            child: Center(child: Text(emoji,
              style: const TextStyle(fontSize: 26)))),
          const SizedBox(width: 14),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: _HighlightText(
                  text: name,
                  query: query,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 15, fontWeight: FontWeight.w800),
                  highlightColor: _indigo)),
                if (isVerified) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_indigo, _pink]),
                      borderRadius: BorderRadius.circular(6)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded,
                          color: Colors.white, size: 9),
                        SizedBox(width: 3),
                        Text('Verified', style: TextStyle(
                          color: Colors.white, fontSize: 8,
                          fontWeight: FontWeight.w800)),
                      ])),
                ],
              ]),
              const SizedBox(height: 4),
              if (branch.isNotEmpty || college.isNotEmpty)
                _HighlightText(
                  text: [
                    if (branch.isNotEmpty) branch,
                    if (college.isNotEmpty) college,
                  ].join(' • '),
                  query: query,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12),
                  highlightColor: _pink),
              if (friendCount > 0) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.people_rounded,
                    color: _green, size: 12),
                  const SizedBox(width: 4),
                  Text('$friendCount friends',
                    style: TextStyle(
                      color: _green, fontSize: 11,
                      fontWeight: FontWeight.w700)),
                ]),
              ],
              const SizedBox(height: 5),
              AsyncBadgeRow(
                userId: user['id']?.toString() ?? '',
                maxVisible: 3,
                chipSize: 16),
            ])),

          Icon(Icons.arrow_forward_ios_rounded,
            color: AppColors.textSecondary(context), size: 14),
        ])));
  }
}

// ══════════════════════════════════════════════════════════
// Post result card
// ══════════════════════════════════════════════════════════
class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String query;
  final void Function(String) onProfileTap;

  const _PostCard({
    required this.post,
    required this.query,
    required this.onProfileTap,
  });

  static const _indigo = Color(0xFF818CF8);
  static const _pink   = Color(0xFFE879F9);
  static const _amber  = Color(0xFFFBBF24);
  static const _green  = Color(0xFF4ADE80);

  String _timeAgo(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inHours < 1)    return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)     return '${diff.inHours}h ago';
    if (diff.inDays == 1)    return 'Yesterday';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _anonColor(String id) {
    final colors = [_indigo, const Color(0xFF00B8A3),
      const Color(0xFFFF375F), _amber];
    return colors[id.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final postId      = post['id']?.toString() ?? '';
    final content     = post['content']?.toString() ?? '';
    final isAnon      = post['is_anonymous'] as bool? ?? true;
    final posterName  = post['poster_name']?.toString() ?? '';
    final posterEmoji = post['poster_emoji']?.toString() ?? '';
    final likes       = (post['likes'] as num?)?.toInt() ?? 0;
    final comments    = (post['comment_count'] as num?)?.toInt() ?? 0;
    final imageUrl    = post['image_url']?.toString();
    final visibility  = post['visibility']?.toString() ?? 'public';

    final showIdentity = !isAnon && posterName.isNotEmpty;
    final displayName  = showIdentity ? posterName : 'Anonymous';
    final displayEmoji = (showIdentity && posterEmoji.isNotEmpty)
        ? posterEmoji
        : '🎭';
    final accentColor  = showIdentity
        ? _indigo
        : _anonColor(postId);

    // Visibility label
    String visLabel; Color visColor;
    switch (visibility) {
      case 'college': visLabel = '🏫 College'; visColor = const Color(0xFF00B8A3); break;
      case 'branch':  visLabel = '🎓 Branch';  visColor = _amber;  break;
      default:        visLabel = '🌍 Public';  visColor = _indigo; break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top accent
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                accentColor.withOpacity(0),
                accentColor.withOpacity(0.6),
                accentColor.withOpacity(0),
              ]),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20)))),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              // Avatar
              GestureDetector(
                onTap: showIdentity && post['user_id'] != null
                  ? () => onProfileTap(post['user_id'].toString())
                  : null,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [
                      accentColor.withOpacity(0.25),
                      accentColor.withOpacity(0.08)]),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withOpacity(0.35), width: 1.5)),
                  child: Center(child: Text(displayEmoji,
                    style: const TextStyle(fontSize: 20))))),
              const SizedBox(width: 10),

              // Name + meta
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(displayName, style: TextStyle(
                      color: accentColor,
                      fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: visColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: visColor.withOpacity(0.3))),
                      child: Text(visLabel, style: TextStyle(
                        color: visColor, fontSize: 9,
                        fontWeight: FontWeight.w800))),
                  ]),
                  Text(_timeAgo(post['created_at']?.toString()),
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11)),
                ])),
            ])),

          // Content with highlight
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: _HighlightText(
              text: content,
              query: query,
              maxLines: 4,
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 14, height: 1.55),
              highlightColor: _pink)),

          // Image thumbnail
          if (imageUrl != null && imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imageUrl,
                  width: double.infinity, height: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()))),

          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              _StatPill(icon: Icons.favorite_rounded,
                value: '$likes', color: Colors.red.shade400),
              const SizedBox(width: 8),
              _StatPill(icon: Icons.chat_bubble_rounded,
                value: '$comments', color: _indigo),
            ])),
        ]));
  }
}

// ══════════════════════════════════════════════════════════
// Highlight text — bolds matched substring
// ══════════════════════════════════════════════════════════
class _HighlightText extends StatelessWidget {
  final String text, query;
  final TextStyle style;
  final Color highlightColor;
  final int? maxLines;

  const _HighlightText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightColor,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null);
    }
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final idx = lower.indexOf(lowerQ);
    if (idx == -1) {
      return Text(text, style: style, maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null);
    }
    return Text.rich(
      TextSpan(children: [
        if (idx > 0)
          TextSpan(text: text.substring(0, idx), style: style),
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: style.copyWith(
            color: highlightColor,
            fontWeight: FontWeight.w900,
            backgroundColor: highlightColor.withOpacity(0.12))),
        if (idx + query.length < text.length)
          TextSpan(
            text: text.substring(idx + query.length),
            style: style),
      ]),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}

// ══════════════════════════════════════════════════════════
// Small reusable widgets
// ══════════════════════════════════════════════════════════
class _TabBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: selected ? const LinearGradient(
            colors: [Color(0xFF818CF8), Color(0xFFE879F9)]) : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? [
            BoxShadow(
              color: const Color(0xFF818CF8).withOpacity(0.3),
              blurRadius: 8, offset: const Offset(0, 3))
          ] : null),
        child: Center(child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white
              : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500)))));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: TextStyle(
      color: AppColors.text(context),
      fontSize: 16, fontWeight: FontWeight.w800)),
    const Spacer(),
    if (trailing != null) trailing!,
  ]);
}

class _HintCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color;
  const _HintCard({required this.emoji, required this.title,
    required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.2)),
      boxShadow: [BoxShadow(
        color: color.withOpacity(0.06),
        blurRadius: 12, offset: const Offset(0, 3))]),
    child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(emoji,
          style: const TextStyle(fontSize: 22)))),
      const SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(
            color: color, fontSize: 14,
            fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12)),
        ])),
      Icon(Icons.search_rounded,
        color: color.withOpacity(0.5), size: 18),
    ]));
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _StatPill({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 4),
      Text(value, style: TextStyle(
        color: color, fontSize: 12,
        fontWeight: FontWeight.w700)),
    ]));
}