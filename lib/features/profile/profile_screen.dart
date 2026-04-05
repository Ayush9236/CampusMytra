import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/login_screen.dart';
import '../settings/privacy_screen.dart';
import '../settings/about_screen.dart';
import '../settings/theme_provider.dart';
import '../auth/college_update_sheet.dart';
import '../badges/badge_system.dart';
import '../admin/admin_panel_screen.dart';
import 'user_profile_screen.dart';
import '../../features/navigation/main_screen.dart' show SettingsScreen;
import '../buzz/comment_poll.dart';
final supabase = Supabase.instance.client;

// ── Royal & Classy Avatar Symbols ─────────────────────────────────────────
const List<Map<String, String>> kAvatarSymbols = [
  // Royalty & Chess
  {'s': '♔', 'l': 'King'},   {'s': '♕', 'l': 'Queen'},
  {'s': '♖', 'l': 'Rook'},   {'s': '♗', 'l': 'Bishop'},
  {'s': '♘', 'l': 'Knight'}, {'s': '♙', 'l': 'Pawn'},
  // Celestial
  {'s': '✦', 'l': 'Star'},    {'s': '✧', 'l': 'Sparkle'},
  {'s': '❋', 'l': 'Bloom'},   {'s': '✺', 'l': 'Radiance'},
  {'s': '⊛', 'l': 'Orb'},     {'s': '✵', 'l': 'Stella'},
  // Geometric Crests
  {'s': '⬡', 'l': 'Hex'},   {'s': '◈', 'l': 'Crest'},
  {'s': '❖', 'l': 'Diamond'},{'s': '⟁', 'l': 'Delta'},
  {'s': '⎔', 'l': 'Shield'}, {'s': '⬟', 'l': 'Penta'},
  // Greek Script
  {'s': 'Ω', 'l': 'Omega'}, {'s': 'Σ', 'l': 'Sigma'},
  {'s': 'Φ', 'l': 'Phi'},   {'s': 'Λ', 'l': 'Lambda'},
  {'s': 'Ψ', 'l': 'Psi'},   {'s': 'Δ', 'l': 'Delta'},
  // Floral Ornaments
  {'s': '❧', 'l': 'Fleur'},      {'s': '✿', 'l': 'Blossom'},
  {'s': '⚜', 'l': 'Fleur-de-lis'},{'s': '☙', 'l': 'Leaf'},
  {'s': '❦', 'l': 'Vine'},       {'s': '✾', 'l': 'Petal'},
  // Arcane & Mystical
  {'s': '⚕', 'l': 'Caduceus'}, {'s': '☯', 'l': 'Yin Yang'},
  {'s': '⚖', 'l': 'Balance'},  {'s': '⚔', 'l': 'Swords'},
  {'s': '⚙', 'l': 'Cog'},      {'s': '⛭', 'l': 'Wheel'},
];

// Legacy emoji list — keeps old profiles rendering correctly
const List<String> kAvatarEmojis = [
  '🎓', '👨‍💻', '👩‍💻', '🧑‍🎓', '🦊', '🐼', '🦁', '🐯',
  '🐸', '🦄', '🐲', '🤖', '👾', '🎮', '⚡', '🔥',
  '🌟', '💎', '🚀', '🎯', '🏆', '🎪', '🦋', '🌈',
];

// ── 30 Rich Banner Themes ──────────────────────────────────────────────────
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

List<Color> kThemeColors(int i) =>
    List<Color>.from(kBannerThemes[i % kBannerThemes.length]['colors'] as List);

// Legacy fallback
const List<List<Color>> kBannerGradients = [
  [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
  [Color(0xFF00B8A3), Color(0xFF00897B)],
  [Color(0xFFFF375F), Color(0xFFE91E63)],
  [Color(0xFFFFB800), Color(0xFFF57C00)],
  [Color(0xFF1A237E), Color(0xFF283593)],
  [Color(0xFF2E7D32), Color(0xFF388E3C)],
  [Color(0xFF4A148C), Color(0xFF6A1B9A)],
  [Color(0xFF880E4F), Color(0xFFAD1457)],
];

const List<String> kBranches = [
  'CS', 'IT', 'ECE', 'EEE', 'ME', 'CE', 'AIDS', 'AIML', 'Other',
];
const List<String> kYears = ['1', '2', '3', '4'];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _matchHistory = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _adminRole;
  int _signupRank = 999999;

  String _selectedEmoji = '♔';
  int _selectedGradientIndex = 0;
  String _bio = '';
  String _username = '';
  BannerRank? _showcaseBannerRank; // null = auto (highest earned)
  // Social counts
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _socialLoading = true;
  List<Map<String, dynamic>> _posts = [];
  bool _postsLoading = true;
  Set<String> _likedPostIds = {};

  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut));
    _loadProfileData();
    _loadSocialData();
    _loadPosts();
    _fetchMyLikes();
    _loadShowcasePref();
  }

  @override
  void dispose() { _headerCtrl.dispose(); super.dispose(); }

  static const _kShowcasePrefKey = 'profile_showcase_banner';

  Future<void> _loadShowcasePref() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kShowcasePrefKey);
    if (stored != null && mounted) {
      final rank = BannerRank.values.where((r) => r.name == stored).firstOrNull;
      if (rank != null) setState(() => _showcaseBannerRank = rank);
    }
  }

  Future<void> _saveShowcasePref(BannerRank? rank) async {
    final prefs = await SharedPreferences.getInstance();
    if (rank == null) {
      await prefs.remove(_kShowcasePrefKey);
    } else {
      await prefs.setString(_kShowcasePrefKey, rank.name);
    }
  }

  void _showBannerPickerSheet(
    List<BannerRank> available,
    BannerRank current,
    Map<String, dynamic> profileMap,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1A1D2E) : Colors.white;
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Choose Banner', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
              color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 4),
            Text('Select which banner to display on your profile',
              style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
            const SizedBox(height: 16),
            ...available.map((rank) {
              final meta = kBanners[rank]!;
              final isSelected = rank == current;
              return GestureDetector(
                onTap: () {
                  setState(() => _showcaseBannerRank = rank);
                  _saveShowcasePref(rank);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: isSelected
                        ? Border.all(color: meta.primary, width: 2)
                        : Border.all(color: Colors.transparent, width: 2),
                    gradient: LinearGradient(
                      colors: [meta.gradientStops[0], meta.gradientStops[2]],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(meta.icon, color: meta.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(meta.title,
                        style: TextStyle(color: meta.primary, fontSize: 14,
                          fontWeight: FontWeight.w900, letterSpacing: 1)),
                      Text(meta.subtitle,
                        style: TextStyle(color: meta.primary.withOpacity(0.7),
                          fontSize: 10, fontWeight: FontWeight.w600)),
                    ])),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: meta.primary, size: 20),
                  ]),
                ),
              );
            }),
          ]),
        );
      },
    );
  }

  Future<void> _loadSocialData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final friendshipsRes = await supabase
          .from('friendships')
          .select('id, sender_id, receiver_id, status')
          .or('sender_id.eq.$userId,receiver_id.eq.$userId');

      final allRows = List<Map<String, dynamic>>.from(
          (friendshipsRes as List).map((e) => Map<String, dynamic>.from(e as Map)));

      final accepted = allRows.where((r) => r['status'] == 'accepted').toList();
      final pending  = allRows.where((r) =>
          r['status'] == 'pending' && r['receiver_id'].toString() == userId).toList();

      final friendIds = accepted.map((r) =>
          r['sender_id'].toString() == userId
              ? r['receiver_id'].toString()
              : r['sender_id'].toString()).toList();

      List<Map<String, dynamic>> friendProfiles = [];
      if (friendIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('id, username, branch, avatar_emoji,banner_index')
              .inFilter('id', friendIds);
          friendProfiles = List<Map<String, dynamic>>.from(
              (profiles as List).map((e) => Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }

      final senderIds = pending.map((r) => r['sender_id'].toString()).toList();
      List<Map<String, dynamic>> pendingProfiles = [];
      if (senderIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('id, username, branch, avatar_emoji')
              .inFilter('id', senderIds);
          final profileMap = {for (final p in profiles as List)
            (p as Map)['id'].toString(): Map<String, dynamic>.from(p)};
          pendingProfiles = pending.map((r) {
            final prof = profileMap[r['sender_id'].toString()] ?? {};
            return {...prof, 'sender_id': r['sender_id'], 'friendship_id': r['id']};
          }).toList();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _friends = friendProfiles;
        _pendingRequests = pendingProfiles;
        _socialLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _loadPosts() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _postsLoading = true);
    try {
      final rows = await supabase
          .from('buzz_feed')
          .select('id, content, created_at, likes, comment_count, image_url')
          .eq('user_id', userId)
          .eq('is_anonymous', false)
          .order('created_at', ascending: false)
          .limit(60);
      if (mounted) setState(() {
        _posts = List<Map<String, dynamic>>.from(
            (rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _postsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  Future<void> _fetchMyLikes() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await supabase.from('buzz_likes').select('post_id').eq('user_id', userId);
      if (mounted) setState(() => _likedPostIds = Set<String>.from(
          (data as List).map((r) => r['post_id'].toString())));
    } catch (_) {}
  }

  Future<void> _toggleLike(String postId, int currentLikes) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final alreadyLiked = _likedPostIds.contains(postId);
    HapticFeedback.lightImpact();
    setState(() {
      if (alreadyLiked) { _likedPostIds.remove(postId); } else { _likedPostIds.add(postId); }
      final idx = _posts.indexWhere((p) => p['id'] == postId);
      if (idx != -1) _posts[idx] = Map.from(_posts[idx])
        ..['likes'] = currentLikes + (alreadyLiked ? -1 : 1);
    });
    try {
      if (alreadyLiked) {
        await supabase.from('buzz_likes').delete().eq('user_id', userId).eq('post_id', postId);
        await supabase.from('buzz_posts').update({'likes': currentLikes - 1}).eq('id', postId);
      } else {
        await supabase.from('buzz_likes').insert({'user_id': userId, 'post_id': postId});
        await supabase.from('buzz_posts').update({'likes': currentLikes + 1}).eq('id', postId);
      }
    } catch (_) {
      if (mounted) setState(() {
        if (alreadyLiked) { _likedPostIds.add(postId); } else { _likedPostIds.remove(postId); }
        final idx = _posts.indexWhere((p) => p['id'] == postId);
        if (idx != -1) _posts[idx] = Map.from(_posts[idx])..['likes'] = currentLikes;
      });
    }
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profileData = await supabase.from('profiles').select().eq('id', userId).single();

      Map<String, dynamic>? statsData;
      try {
        statsData = await supabase.from('game_stats').select().eq('user_id', userId).maybeSingle();
      } catch (_) {}

      String? adminRole;
      int signupRank = 999999;
      try {
        final result = await supabase.rpc('get_user_badge_data', params: {'p_user_id': userId});
        if (result != null) {
          final row = (result is List && result.isNotEmpty)
              ? Map<String, dynamic>.from(result.first as Map)
              : Map<String, dynamic>.from(result as Map);
          adminRole  = row['admin_role']?.toString();
          signupRank = (row['signup_rank'] as num?)?.toInt() ?? 999999;
        }
      } catch (_) {}

      List<Map<String, dynamic>> matchesData = [];
      try {
        final result = await supabase
            .from('match_history')
            .select('winner_id, loser_id, game_type, was_quit, created_at, room_id, all_player_ids')
            .or('winner_id.eq.$userId,loser_id.eq.$userId')
            .order('created_at', ascending: false)
            .limit(5);
        for (final match in (result as List)) {
          matchesData.add(Map<String, dynamic>.from(match));
        }
      } catch (_) {}

      // Supplement with finished games from multi_game_rooms (catches quit games
      // whose match_history insert failed due to RLS or missing DB trigger)
      try {
        final roomsResult = await supabase
            .from('multi_game_rooms')
            .select('id, winner_id, last_place_id, player_order, updated_at')
            .eq('status', 'finished')
            .not('last_place_id', 'is', null)
            .or('winner_id.eq.$userId,last_place_id.eq.$userId')
            .order('updated_at', ascending: false)
            .limit(5);

        final existingIds =
            matchesData.map((m) => m['room_id']?.toString()).toSet();
        for (final room in (roomsResult as List)) {
          final roomId = room['id']?.toString();
          if (roomId == null || existingIds.contains(roomId)) continue;
          matchesData.add({
            'room_id':        roomId,
            'winner_id':      room['winner_id'],
            'loser_id':       room['last_place_id'],
            'game_type':      'uno_multiplayer',
            'was_quit':       true,
            'created_at':     room['updated_at'],
            'all_player_ids': room['player_order'],
          });
        }

        // Re-sort merged list newest-first, keep top 20
        matchesData.sort((a, b) {
          final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0);
          final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0);
          return db.compareTo(da);
        });
        if (matchesData.length > 5) matchesData = matchesData.sublist(0, 5);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _profile = profileData;
        final savedEmoji = (profileData['avatar_emoji'] as String?)?.trim() ?? '';
        _selectedEmoji = savedEmoji.isNotEmpty ? savedEmoji : '♔';
        _selectedGradientIndex = ((profileData['banner_index'] as num?)?.toInt() ?? 0)
            .clamp(0, kBannerThemes.length - 1);
        _bio = (profileData['bio'] as String?) ?? '';

        _stats = statsData ?? {'games_played': 0, 'games_won': 0, 'games_lost': 0, 'win_streak': 0, 'best_win_streak': 0};
        _matchHistory = matchesData;
        _adminRole = adminRole;
        _signupRank = signupRank;
        _isLoading = false;
      });
      _headerCtrl.forward(from: 0);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Profile load error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8)));
      }
    }
  }

  Future<void> _saveCustomization({
    required String emoji, required int gradientIndex, required String bio,
    required String name, required String branch, required String year,
    String? username,
  }) async {
    setState(() => _isSaving = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final Map<String, dynamic> updates = {
        'avatar_emoji': emoji, 'banner_index': gradientIndex, 'bio': bio,
        'name': name, 'branch': branch, 'year': year,
      };

      // Handle username change with 30-day limit
      final currentUsername = _profile?['username']?.toString() ?? '';
      final newUsername = (username ?? '').trim().toLowerCase();
      if (newUsername.isNotEmpty && newUsername != currentUsername) {
        // Check 30-day cooldown
        final changedAt = _profile?['username_changed_at'];
        if (changedAt != null) {
          final lastChange = DateTime.parse(changedAt.toString()).toLocal();
          final daysSince = DateTime.now().difference(lastChange).inDays;
          if (daysSince < 30) {
            final nextChange = lastChange.add(const Duration(days: 30));
            if (mounted) {
              setState(() => _isSaving = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('❌ Username can only be changed once per month. Try after ${nextChange.day}/${nextChange.month}/${nextChange.year}.'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4)));
            }
            return;
          }
        }
        // Check uniqueness
        try {
          final existing = await supabase.from('profiles')
              .select('id').eq('username', newUsername).neq('id', userId).maybeSingle();
          if (existing != null) {
            if (mounted) {
              setState(() => _isSaving = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('❌ Username already taken. Choose another.'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating));
            }
            return;
          }
        } catch (_) {}
        updates['username'] = newUsername;
        updates['username_changed_at'] = DateTime.now().toUtc().toIso8601String();
      }

      await supabase.from('profiles').update(updates).eq('id', userId);
      if (mounted) {
        setState(() {
          _selectedEmoji = emoji; _selectedGradientIndex = gradientIndex; _bio = bio;
          if (_profile != null) {
            _profile!['name'] = name; _profile!['branch'] = branch; _profile!['year'] = year;
            if (updates.containsKey('username')) {
              _profile!['username'] = newUsername;
              _profile!['username_changed_at'] = updates['username_changed_at'];
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Profile saved!'),
          backgroundColor: Color(0xFF00B8A3),
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        await _loadProfileData();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Save failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  double get _winRate {
    final played = _stats?['games_played'] ?? 0;
    if (played == 0) return 0.0;
    return ((_stats?['games_won'] ?? 0) / played * 100);
  }

  void _showCustomizeSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _CustomizeBottomSheet(
        selectedEmoji: _selectedEmoji, selectedGradientIndex: _selectedGradientIndex,
        bio: _bio, name: _profile?['name']?.toString() ?? '',
        branch: _profile?['branch']?.toString() ?? '',
        year: _profile?['year']?.toString() ?? '',
        username: _profile?['username']?.toString() ?? '',
        usernameChangedAt: _profile?['username_changed_at']?.toString(),
        onSave: (emoji, gradientIndex, bio, name, branch, year, username) {
          _saveCustomization(emoji: emoji, gradientIndex: gradientIndex,
            bio: bio, name: name, branch: branch, year: year, username: username);
        },
      ),
    );
  }

  void _showCollegeUpdateSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => const UpdateCollegeSheet(),
    ).then((updated) { if (updated == true) _loadProfileData(); });
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surface = AppColors.surface(context);
    final borderColor = AppColors.border(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background(context),
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('♔', style: TextStyle(fontSize: 48, color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          CircularProgressIndicator(color: Theme.of(context).primaryColor, strokeWidth: 2),
        ])));
    }

    final gradient  = kThemeColors(_selectedGradientIndex);
    final name      = _profile?['name']?.toString() ?? 'User';
    final branch    = _profile?['branch']?.toString() ?? '';
    final year      = _profile?['year']?.toString() ?? '';

    final collegeStatus  = _profile?['college_status']?.toString();
    final collegeId      = _profile?['college_id']?.toString();
    final hasCollegeName = (_profile?['college_name']?.toString().isNotEmpty ?? false);
    final isPending      = collegeStatus == 'pending' ||
        (collegeId == null && hasCollegeName && collegeStatus != 'verified' &&
         collegeStatus != 'rejected' && collegeStatus != 'blocked');
    final isRejected  = collegeStatus == 'rejected';
    final hasCollege  = collegeId != null || hasCollegeName;
    final collegeName = _profile?['college_name']?.toString() ?? '';
    final branchName  = _profile?['branch_name']?.toString() ?? '';
    final studentId   = _profile?['student_id']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfileData,
          color: Theme.of(context).primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(children: [

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
                child: Row(children: [
                  Expanded(child: Text('Profile', style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w900,
                    color: textColor, letterSpacing: -0.5))),
                  _TopBarBtn(icon: Icons.edit_outlined, label: 'Edit',
                    color: Theme.of(context).primaryColor, onTap: _showCustomizeSheet),
                  const SizedBox(width: 8),
                  _TopBarBtn(icon: Icons.settings_outlined, label: 'Settings',
                    color: Colors.grey, onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                  const SizedBox(width: 8),
                  _TopBarBtn(icon: Icons.logout_rounded, label: 'Out',
                    color: Colors.red, onTap: _logout),
                ]),
              ),
              const SizedBox(height: 20),

              FadeTransition(
                opacity: _headerFade,
                child: SlideTransition(
                  position: _headerSlide,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _HeroCard(
                      gradient: gradient, emoji: _selectedEmoji,
                      name: name, email: _profile?['email']?.toString() ?? '',
                      branch: branch, year: year, bio: _bio,
                      coins: _profile?['coins'] ?? 0,
                      studentId: studentId,
                      username: _profile?['username']?.toString() ?? '',
                      bannerRank: () {
                        final pm = {
                          'user_id':     supabase.auth.currentUser?.id ?? '',
                          'admin_role':  _adminRole,
                          'signup_rank': _signupRank,
                          'uno_wins':    (_stats?['uno_wins'] as num?)?.toInt() ?? 0,
                          'dsa_wins':    (_stats?['dsa_wins'] as num?)?.toInt() ?? 0,
                          'post_count':  (_profile!['post_count'] as num?)?.toInt() ?? 0,
                          'max_post_likes': (_profile!['max_post_likes'] as num?)?.toInt() ?? 0,
                          'friend_count':   (_profile!['friend_count'] as num?)?.toInt() ?? 0,
                        };
                        final avail = computeAvailableBanners(pm);
                        return (_showcaseBannerRank != null && avail.contains(_showcaseBannerRank!))
                            ? _showcaseBannerRank!
                            : computeBannerRank(pm);
                      }(),
                      onEditTap: _showCustomizeSheet, isSaving: _isSaving),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (_profile != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: BadgeSection(profile: {
                    ..._profile!,
                    'user_id':    supabase.auth.currentUser?.id ?? '',
                    'admin_role': _adminRole,
                    'signup_rank': _signupRank,
                    'uno_wins':  (_stats?['uno_wins']  as num?)?.toInt() ?? 0,
                    'dsa_wins':  (_stats?['dsa_wins']  as num?)?.toInt() ?? 0,
                    'post_count':     (_profile!['post_count']     as num?)?.toInt() ?? 0,
                    'max_post_likes': (_profile!['max_post_likes'] as num?)?.toInt() ?? 0,
                    'friend_count':   (_profile!['friend_count']   as num?)?.toInt() ?? 0,
                  }),
                ),
              const SizedBox(height: 10),
              if (_profile != null) () {
                final profileMap = {
                  'user_id':     supabase.auth.currentUser?.id ?? '',
                  'admin_role':  _adminRole,
                  'signup_rank': _signupRank,
                  'uno_wins':    (_stats?['uno_wins'] as num?)?.toInt() ?? 0,
                  'dsa_wins':    (_stats?['dsa_wins'] as num?)?.toInt() ?? 0,
                  'post_count':  (_profile!['post_count'] as num?)?.toInt() ?? 0,
                  'max_post_likes': (_profile!['max_post_likes'] as num?)?.toInt() ?? 0,
                  'friend_count':   (_profile!['friend_count'] as num?)?.toInt() ?? 0,
                };
                final available = computeAvailableBanners(profileMap);
                final autoBr    = computeBannerRank(profileMap);
                final br = (_showcaseBannerRank != null && available.contains(_showcaseBannerRank!))
                    ? _showcaseBannerRank!
                    : autoBr;
                if (br == BannerRank.none && available.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (br != BannerRank.none) BannerNameplate(bannerRank: br),
                    if (available.length > 1) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _showBannerPickerSheet(available, br, profileMap),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.swap_horiz_rounded, size: 14, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 4),
                          Text('Choose banner to showcase',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ]),
                );
              }(),
              const SizedBox(height: 14),

              if (isPending || isRejected)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _CollegeVerificationBanner(
                    status: collegeStatus ?? 'pending',
                    collegeName: collegeName,
                    onUpdate: _showCollegeUpdateSheet),
                ),
              if (isPending || isRejected) const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: hasCollege
                  ? _CollegeInfoCard(
                      collegeName: collegeName,
                      branchName: branchName.isNotEmpty ? branchName : branch,
                      studentId: studentId,
                      isPending: isPending,
                      isRejected: isRejected,
                      onUpdate: _showCollegeUpdateSheet)
                  : _CollegeSetupBanner(onTap: _showCollegeUpdateSheet),
              ),
              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: _SocialNavTile(
                    icon: Icons.people_rounded,
                    label: 'Friends',
                    count: _friends.length,
                    color: const Color(0xFF818CF8),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _SocialScreen(
                        initialTab: 0,
                        friends: _friends,
                        pendingRequests: _pendingRequests,
                        loading: _socialLoading,
                        onRefresh: _loadSocialData,
                        posts: _posts,
                        postsLoading: _postsLoading,
                        likedPostIds: _likedPostIds,
                        onLike: _toggleLike,
                      ))),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _SocialNavTile(
                    icon: Icons.mark_email_unread_rounded,
                    label: 'Requests',
                    count: _pendingRequests.length,
                    color: const Color(0xFFFFB800),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _SocialScreen(
                        initialTab: 1,
                        friends: _friends,
                        pendingRequests: _pendingRequests,
                        loading: _socialLoading,
                        onRefresh: _loadSocialData,
                        posts: _posts,
                        postsLoading: _postsLoading,
                        likedPostIds: _likedPostIds,
                        onLike: _toggleLike,
                      ))),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _SocialNavTile(
                    icon: Icons.dynamic_feed_rounded,
                    label: 'Posts',
                    count: _posts.length,
                    color: const Color(0xFF4ADE80),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _SocialScreen(
                        initialTab: 2,
                        friends: _friends,
                        pendingRequests: _pendingRequests,
                        loading: _socialLoading,
                        onRefresh: _loadSocialData,
                        posts: _posts,
                        postsLoading: _postsLoading,
                        likedPostIds: _likedPostIds,
                        onLike: _toggleLike,
                      ))),
                  )),
                ]),
              ),
              const SizedBox(height: 24),

              const SizedBox(height: 24),

              Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _StatsSection(stats: _stats, winRate: _winRate)),
              const SizedBox(height: 24),

              Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _InviteCard()),
              const SizedBox(height: 24),

              Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MatchHistorySection(
                  matchHistory: _matchHistory,
                  userId: supabase.auth.currentUser?.id ?? '')),
              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(color: surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor)),
                  child: Column(children: [
                    _SettingsTile(icon: Icons.admin_panel_settings_rounded, label: 'Admin Panel',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminGateScreen()))),
                    Divider(height: 1, color: borderColor),
                    _SettingsTile(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()))),
                    Divider(height: 1, color: borderColor),
                    _SettingsTile(icon: Icons.info_outline, label: 'About CampusMytra',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
                  ]),
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPORTING WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SocialNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _SocialNavTile({required this.icon, required this.label, required this.count, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.surface(context);
    final border  = AppColors.border(context);
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text('$count', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _SocialScreen extends StatefulWidget {
  final int initialTab;
  final List<Map<String, dynamic>> friends;
  final List<Map<String, dynamic>> pendingRequests;
  final bool loading;
  final VoidCallback onRefresh;
  final List<Map<String, dynamic>> posts;
  final bool postsLoading;
  final Set<String> likedPostIds;
  final Future<void> Function(String, int) onLike;

  const _SocialScreen({
    required this.initialTab,
    required this.friends,
    required this.pendingRequests,
    required this.loading,
    required this.onRefresh,
    required this.posts,
    required this.postsLoading,
    required this.likedPostIds,
    required this.onLike,
  });

  @override
  State<_SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<_SocialScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bg          = AppColors.background(context);
    final textColor   = AppColors.text(context);
    final surfaceVar  = AppColors.surfaceVariant(context);
    final textSecondary = AppColors.textSecondary(context);
    final primary     = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context)),
        title: Text('Social', style: TextStyle(color: textColor, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              decoration: BoxDecoration(color: surfaceVar, borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(10)),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: textSecondary,
                labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                tabs: [
                  Tab(text: '👥 Friends (${widget.friends.length})'),
                  Tab(text: '📨 Requests (${widget.pendingRequests.length})'),
                  Tab(text: '📝 Posts (${widget.posts.length})'),
                ],
              ),
            ),
          )),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _FriendsTab(friends: widget.friends, loading: widget.loading, textColor: textColor, textSecondary: textSecondary, surfaceVar: surfaceVar),
          _RequestsTab(requests: widget.pendingRequests, loading: widget.loading, textColor: textColor, textSecondary: textSecondary, surfaceVar: surfaceVar, onRefresh: widget.onRefresh),
          _PostsTab(posts: widget.posts, loading: widget.postsLoading, likedPostIds: widget.likedPostIds, onLike: widget.onLike, onOpenComments: (postId, ownerId, content) =>
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => CommentsSheet(
                postId: postId,
                postOwnerId: ownerId,
                isAnonymousPost: false,
                postContent: content))),
        ],
      ),
    );
  }
}

class _RequestBtn extends StatelessWidget {
  final String label; final Color color; final VoidCallback onTap;
  const _RequestBtn({required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 32, height: 32,
      decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5))),
      child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)))));
}

// ── FIXED: _CollegeInfoCard — branch + studentId wrapped in Flexible ──
class _CollegeInfoCard extends StatelessWidget {
  final String collegeName, branchName, studentId;
  final bool isPending, isRejected;
  final VoidCallback onUpdate;
  const _CollegeInfoCard({required this.collegeName, required this.branchName,
    required this.studentId, required this.onUpdate,
    this.isPending = false, this.isRejected = false});

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = isRejected ? Colors.red.withOpacity(0.5)
        : isPending ? const Color(0xFFFFB800).withOpacity(0.4)
        : const Color(0xFF00B8A3).withOpacity(0.35);
    final bgColor = isRejected ? Colors.red.withOpacity(0.05)
        : isPending ? const Color(0xFFFFB800).withOpacity(0.05)
        : const Color(0xFF00B8A3).withOpacity(0.08);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('🏫', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Expanded(child: Text(collegeName, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Color(0xFF00B8A3),
                fontWeight: FontWeight.w800, fontSize: 13))),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Text('🎓', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(branchName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textSecondary, fontSize: 12))),
            if (studentId.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('•', style: TextStyle(color: textSecondary.withOpacity(0.4))),
              const SizedBox(width: 8),
              Flexible(
                child: Text('🪪 $studentId',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFFFB800),
                    fontSize: 12,
                    fontWeight: FontWeight.w700))),
            ],
          ]),
        ])),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onUpdate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00B8A3).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00B8A3).withOpacity(0.4))),
            child: Text('Update', style: TextStyle(
              color: Color(0xFF00B8A3), fontSize: 12, fontWeight: FontWeight.w800)))),
      ]));
  }
}

class _CollegeVerificationBanner extends StatelessWidget {
  final String status, collegeName;
  final VoidCallback onUpdate;
  const _CollegeVerificationBanner({required this.status, required this.collegeName, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    final color = isPending ? const Color(0xFFFFB800) : Colors.red;
    final icon  = isPending ? '⏳' : '❌';
    final title = isPending ? 'College Pending Verification' : 'College Verification Failed';
    final subtitle = isPending
        ? 'Owner is reviewing "$collegeName". You have limited access until verified.'
        : 'Your college "$collegeName" was not verified. Please update it or contact support.';
    return GestureDetector(
      onTap: isPending ? null : onUpdate,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(icon, style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
            if (!isPending) ...[
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('Tap to update college →',
                  style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w700))),
            ],
          ])),
        ])));
  }
}

class _CollegeSetupBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CollegeSetupBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB800).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.5), width: 1.5)),
      child: Row(children: [
        Text('🏫', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Set Your College & Branch',
            style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.w800, fontSize: 14)),
          Text('Required for College & Branch Buzz feeds',
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFFB800), size: 15),
      ])));
}

class _TopBarBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _TopBarBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16), const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ])));
}

// ── HERO CARD ──
class _HeroCard extends StatelessWidget {
  final List<Color> gradient;
  final String emoji, name, email, branch, year, bio, studentId, username;
  final int coins;
  final VoidCallback onEditTap;
  final bool isSaving;
  final BannerRank bannerRank;

  const _HeroCard({required this.gradient, required this.emoji, required this.name,
    required this.email, required this.branch, required this.year, required this.bio,
    required this.coins, required this.onEditTap, required this.isSaving,
    this.studentId = '', this.username = '', this.bannerRank = BannerRank.none});

  bool get _isLegacyEmoji => kAvatarEmojis.contains(emoji);

  @override
  Widget build(BuildContext context) {
    final branchClean = (branch == 'null' || branch.isEmpty) ? null : branch;
    final yearClean   = (year   == 'null' || year.isEmpty)   ? null : year;
    final tag = (branchClean != null && yearClean != null)
        ? '$branchClean • Year $yearClean'
        : branchClean ?? (yearClean != null ? 'Year $yearClean' : 'Student');

    return ProfileBannerWidget(
      bannerRank: bannerRank,
      fallbackGradient: gradient,
      child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(width: 88, height: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15), shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                child: Center(child: Text(emoji,
                  style: TextStyle(
                    fontSize: _isLegacyEmoji ? 44 : 34,
                    color: AppColors.text(context),
                    fontWeight: FontWeight.w900)))),
              Positioned(right: 0, bottom: 0, child: GestureDetector(
                onTap: onEditTap,
                child: Container(width: 28, height: 28,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.edit, size: 14, color: gradient[0])))),
            ]),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: -0.3)),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('@$username', style: TextStyle(
                  fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 4),
              Text(email, style: TextStyle(fontSize: 12, color: Colors.white60),
                overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(tag, style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.w700, fontSize: 12))),
              if (studentId.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text('🪪 $studentId', style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 11))),
              ],
            ])),
          ]),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14)),
              child: Text('"$bio"', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13,
                  fontStyle: FontStyle.italic, height: 1.4))),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('🪙', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Text('$coins', style: TextStyle(fontSize: 32,
                fontWeight: FontWeight.w900, color: AppColors.text(context))),
              const SizedBox(width: 6),
              Text('coins', style: TextStyle(fontSize: 15, color: Colors.white60)),
            ])),
        ])),
    );
  }
}

class _HeroBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 80, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 60, paint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.8), 40, paint);
  }
  @override bool shouldRepaint(_) => false;
}

class _StatsSection extends StatelessWidget {
  final Map<String, dynamic>? stats; final double winRate;
  const _StatsSection({required this.stats, required this.winRate});

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('📊 Statistics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _StatCard(title: 'Games', value: '${stats?['games_played'] ?? 0}', icon: Icons.sports_esports, color: Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(title: 'Wins', value: '${stats?['games_won'] ?? 0}', icon: Icons.emoji_events, color: Colors.green)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _StatCard(title: 'Losses', value: '${stats?['games_lost'] ?? 0}', icon: Icons.trending_down, color: Colors.red)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(title: 'Win Rate', value: '${winRate.toStringAsFixed(1)}%', icon: Icons.percent, color: Colors.orange)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _StatCard(title: 'Streak', value: '${stats?['win_streak'] ?? 0}', icon: Icons.local_fire_department, color: Colors.deepOrange)),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(title: 'Best', value: '${stats?['best_win_streak'] ?? 0}', icon: Icons.star, color: Colors.amber)),
      ]),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String title, value; final IconData icon; final Color color;
  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.25))),
    child: Column(children: [
      Icon(icon, color: color, size: 28), const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
      Text(title, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), fontWeight: FontWeight.w600)),
    ]));
}

class _InviteCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.green.withOpacity(0.4), width: 1.5)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.share_rounded, color: Colors.green), const SizedBox(width: 8),
          Text('Invite Friends!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor))]),
        const SizedBox(height: 8),
        Text('Share CampusMytra with your friends and play together!',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: textSecondary)),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () {
            Clipboard.setData(const ClipboardData(text: '🃏 Play UNO & DSA Combat with me on CampusMytra!'));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ Copied!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.35), blurRadius: 12)]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy, color: Colors.white, size: 16), SizedBox(width: 8),
              Text('Copy Invite Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]))),
      ]));
  }
}

class _MatchHistorySection extends StatelessWidget {
  final List<Map<String, dynamic>> matchHistory; final String userId;
  const _MatchHistorySection({required this.matchHistory, required this.userId});

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('🎮 Recent Matches', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
        Text('Last 5', style: TextStyle(color: textSecondary, fontSize: 13))]),
      const SizedBox(height: 14),
      if (matchHistory.isEmpty)
        Container(padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: AppColors.surfaceVariant(context), borderRadius: BorderRadius.circular(16)),
          child: Center(child: Column(children: [
            Icon(Icons.sports_esports_outlined, size: 48, color: textSecondary),
            const SizedBox(height: 12),
            Text('No matches yet', style: TextStyle(fontSize: 15, color: textSecondary))])))
      else
        ...matchHistory.map((match) {
          final iWon    = match['winner_id'] == userId;
          final wasQuit = match['was_quit'] == true;
          return _MatchHistoryCard(
            iWon: iWon,
            coinsChange: iWon ? '+50' : (wasQuit ? '-30' : '-20'),
            date: match['created_at']?.toString() ?? '',
            gameType: match['game_type']?.toString() ?? 'uno_win',
            wasQuit: match['was_quit'] == true,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => _MatchDetailScreen(match: match, userId: userId))),
          );
        }),
    ]);
  }
}

class _MatchHistoryCard extends StatelessWidget {
  final bool iWon, wasQuit;
  final String coinsChange, date, gameType;
  final VoidCallback onTap;
  const _MatchHistoryCard({
    required this.iWon,
    required this.coinsChange,
    required this.date,
    required this.gameType,
    required this.wasQuit,
    required this.onTap,
  });

  String get _gameEmoji => gameType.startsWith('dsa') ? '⚔️' : '🃏';
  String get _gameLabel => gameType.startsWith('dsa') ? 'DSA' : 'UNO';

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(d);
      if (diff.inDays == 0) return diff.inHours == 0 ? '${diff.inMinutes}m ago' : '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = iWon ? Colors.green : Colors.red;
    final label = wasQuit ? (iWon ? 'Win (quit)' : 'Loss (quit)') : (iWon ? 'Victory' : 'Defeat');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.withOpacity(0.05), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withOpacity(0.25))),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: c.withOpacity(0.12), shape: BoxShape.circle),
            child: Center(child: Text(_gameEmoji, style: TextStyle(fontSize: 22)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c)),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(_gameLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c))),
            ]),
            const SizedBox(height: 2),
            Text(_formatDate(date), style: TextStyle(fontSize: 11, color: AppColors.textHint(context))),
          ])),
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(coinsChange, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
              Text('🪙', style: TextStyle(fontSize: 14)),
            ]),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: c.withOpacity(0.5), size: 18),
          ]),
        ])));
  }
}

// ── Match Detail Screen ────────────────────────────────────────────────────────
class _MatchDetailScreen extends StatefulWidget {
  final Map<String, dynamic> match;
  final String userId;
  const _MatchDetailScreen({required this.match, required this.userId});
  @override
  State<_MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<_MatchDetailScreen> {
  // Each entry: {player_id, name, branch, rank}
  // rank 1 = winner, highest rank = last place, 0 = middle players (not ranked)
  List<Map<String, dynamic>> _players = [];
  bool _loading = true;

  String get _gameEmoji => (widget.match['game_type']?.toString() ?? '').startsWith('dsa') ? '⚔️' : '🃏';
  String get _gameLabel => (widget.match['game_type']?.toString() ?? '').startsWith('dsa') ? 'DSA Combat' : 'UNO Multiplayer';

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inDays == 0) return diff.inHours == 0 ? '${diff.inMinutes}m ago' : '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year} at ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    final roomId   = widget.match['room_id']?.toString();
    final winnerId = widget.match['winner_id']?.toString() ?? '';
    final loserId  = widget.match['loser_id']?.toString() ?? '';

    List<Map<String, dynamic>> players = [];

    try {
      // Try all_player_ids from match_history first (stored by process_uno_game_end)
      final rawIds = widget.match['all_player_ids'];
      List<String> allIds = [];

      if (rawIds != null && rawIds is List && rawIds.isNotEmpty) {
        allIds = rawIds.map((e) => e.toString()).toList();
      } else if (roomId != null && roomId.isNotEmpty) {
        // Fallback: try multi_player_hands (exists for recent games)
        final hands = await supabase
            .from('multi_player_hands')
            .select('player_id')
            .eq('room_id', roomId);
        allIds = (hands as List)
            .map((h) => h['player_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }

      if (allIds.isNotEmpty) {
        final profiles = await supabase
            .from('profiles')
            .select('id, username, branch')
            .inFilter('id', allIds);

        final profileMap = <String, Map<String, dynamic>>{};
        for (final p in profiles as List) {
          profileMap[p['id'].toString()] = Map<String, dynamic>.from(p as Map);
        }

        for (final pid in allIds) {
          final prof = profileMap[pid] ?? {};
          int rank = 0;
          if (pid == winnerId) rank = 1;
          else if (pid == loserId) rank = 99;
          players.add({
            'player_id': pid,
            'name': prof['username']?.toString() ?? 'Unknown',
            'branch': prof['branch']?.toString() ?? '',
            'rank': rank,
          });
        }

        players.sort((a, b) {
          final ra = a['rank'] as int;
          final rb = b['rank'] as int;
          if (ra == 1) return -1;
          if (rb == 1) return 1;
          if (ra == 99) return 1;
          if (rb == 99) return -1;
          return 0;
        });
      }
    } catch (_) {}

    // Fallback: fetch real names for winner + loser from profiles
    if (players.isEmpty) {
      final ids = [winnerId, loserId].where((id) => id.isNotEmpty).toList();
      try {
        final profs = await supabase.from('profiles').select('id, username, branch').inFilter('id', ids);
        final profMap = <String, Map<String, dynamic>>{};
        for (final p in profs as List) { profMap[p['id'].toString()] = Map<String, dynamic>.from(p as Map); }
        players = [
          {'player_id': winnerId, 'name': profMap[winnerId]?['username']?.toString() ?? 'Unknown', 'branch': profMap[winnerId]?['branch']?.toString() ?? '', 'rank': 1},
          if (loserId.isNotEmpty)
            {'player_id': loserId,  'name': profMap[loserId]?['username']?.toString()  ?? 'Unknown', 'branch': profMap[loserId]?['branch']?.toString()  ?? '', 'rank': 99},
        ];
      } catch (_) {
        players = [
          {'player_id': winnerId, 'name': 'Unknown', 'branch': '', 'rank': 1},
          if (loserId.isNotEmpty)
            {'player_id': loserId,  'name': 'Unknown', 'branch': '', 'rank': 99},
        ];
      }
    }

    if (mounted) setState(() { _players = players; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final bg            = AppColors.background(context);
    final textColor     = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surface       = AppColors.surface(context);
    final border        = AppColors.border(context);

    final iWon      = widget.match['winner_id'] == widget.userId;
    final wasQuit   = widget.match['was_quit'] == true;
    final resultColor = iWon ? Colors.green : Colors.red;
    final resultLabel = wasQuit
        ? (iWon ? 'Victory (opponent quit)' : 'Defeat (you quit)')
        : (iWon ? 'Victory' : 'Defeat');
    final resultEmoji = iWon ? '🏆' : '💀';
    final coinsLabel  = iWon ? '+50 coins' : '-20 coins';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
          color: textColor),
        title: Text('Match Details',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Result hero card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: resultColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: resultColor.withOpacity(0.35), width: 1.5)),
            child: Column(children: [
              Text(resultEmoji, style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(resultLabel,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: resultColor)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(coinsLabel,
                  style: TextStyle(color: resultColor, fontSize: 16, fontWeight: FontWeight.w800))),
              const SizedBox(height: 8),
              Text(_formatDate(widget.match['created_at']?.toString() ?? ''),
                style: TextStyle(color: textSecondary, fontSize: 12)),
            ]),
          ),

          const SizedBox(height: 20),

          // ── Game type ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border)),
            child: Row(children: [
              Text(_gameEmoji, style: TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Game Mode', style: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                Text(_gameLabel, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),

          const SizedBox(height: 20),

          // ── All Players ──
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('All Players', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor)),
            if (!_loading)
              Text('${_players.length} players',
                style: TextStyle(color: textSecondary, fontSize: 12)),
          ]),
          const SizedBox(height: 10),

          if (_loading)
            Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor, strokeWidth: 2)))
          else
            ..._players.asMap().entries.map((entry) {
              final idx    = entry.key;
              final player = entry.value;
              final pid    = player['player_id']?.toString() ?? '';
              final isMe   = pid == widget.userId;
              final rank   = player['rank'] as int;
              final isWinner   = rank == 1;
              final isLastPlace = rank == 99;
              final isMiddle   = !isWinner && !isLastPlace;

              // Label and color per position
              final String rankLabel;
              final Color rankColor;
              if (isWinner) {
                rankLabel = '🏆 Winner';
                rankColor = Colors.green;
              } else if (isLastPlace) {
                rankLabel = '💀 Last Place';
                rankColor = Colors.red;
              } else {
                rankLabel = '😐 Finished';
                rankColor = const Color(0xFF818CF8);
              }

              final playerName = player['name']?.toString() ?? 'Unknown';
              final displayName = isMe ? '$playerName (You)' : playerName;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: pid.isNotEmpty ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => UserProfileScreen(userId: pid))) : null,
                  child: _PlayerResultRow(
                    rankLabel: rankLabel,
                    name: displayName,
                    branch: player['branch']?.toString() ?? '',
                    color: rankColor,
                    textColor: textColor,
                    textSecondary: textSecondary,
                    position: idx + 1,
                  ),
                ),
              );
            }),

          if (wasQuit) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withOpacity(0.35))),
              child: Row(children: [
                Text('⚠️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  iWon ? 'Someone left the game early' : 'You left the game early (-20 coins deducted)',
                  style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],

          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _PlayerResultRow extends StatelessWidget {
  final String rankLabel, name, branch;
  final Color color, textColor, textSecondary;
  final int position;
  const _PlayerResultRow({
    required this.rankLabel, required this.name, required this.branch,
    required this.color, required this.textColor, required this.textSecondary,
    required this.position,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Row(children: [
      // Position number circle
      Container(width: 40, height: 40,
        decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
        child: Center(child: Text('$position',
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rankLabel, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(name, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
        if (branch.isNotEmpty)
          Text(branch, style: TextStyle(color: textSecondary, fontSize: 12)),
      ])),
    ]),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).primaryColor),
    title: Text(label, style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.w600)),
    trailing: Icon(Icons.arrow_forward_ios, size: 15, color: AppColors.textSecondary(context)),
    onTap: onTap);
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOMIZE BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _CustomizeBottomSheet extends StatefulWidget {
  final String selectedEmoji, bio, name, branch, year, username;
  final String? usernameChangedAt;
  final int selectedGradientIndex;
  final Function(String emoji, int gradientIndex, String bio,
      String name, String branch, String year, String username) onSave;

  const _CustomizeBottomSheet({required this.selectedEmoji, required this.selectedGradientIndex,
    required this.bio, required this.name, required this.branch,
    required this.year, this.username = '', this.usernameChangedAt,
    required this.onSave});

  @override
  State<_CustomizeBottomSheet> createState() => _CustomizeBottomSheetState();
}

class _CustomizeBottomSheetState extends State<_CustomizeBottomSheet>
    with SingleTickerProviderStateMixin {
  late String _emoji;
  late int _gradientIndex;
  late TextEditingController _bioCtrl, _nameCtrl, _usernameCtrl;
  String? _selectedBranch, _selectedYear;
  late TabController _tabCtrl;

  bool get _usernameChangeCoolingDown {
    final changedAt = widget.usernameChangedAt;
    if (changedAt == null) return false;
    try {
      final lastChange = DateTime.parse(changedAt).toLocal();
      return DateTime.now().difference(lastChange).inDays < 30;
    } catch (_) { return false; }
  }

  String get _nextChangeDate {
    try {
      final lastChange = DateTime.parse(widget.usernameChangedAt!).toLocal();
      final next = lastChange.add(const Duration(days: 30));
      return '${next.day}/${next.month}/${next.year}';
    } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();
    _emoji = widget.selectedEmoji;
    _gradientIndex = widget.selectedGradientIndex;
    _bioCtrl = TextEditingController(text: widget.bio);
    _nameCtrl = TextEditingController(text: widget.name);
    _usernameCtrl = TextEditingController(text: widget.username);
    _selectedBranch = kBranches.contains(widget.branch) ? widget.branch : null;
    _selectedYear   = kYears.contains(widget.year)   ? widget.year   : null;
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _bioCtrl.dispose(); _nameCtrl.dispose(); _usernameCtrl.dispose(); _tabCtrl.dispose(); super.dispose(); }

  bool get _isLegacyEmoji => kAvatarEmojis.contains(_emoji);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF151825) : Colors.white;
    final textColor     = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceVar    = AppColors.surfaceVariant(context);
    final primary       = Theme.of(context).primaryColor;
    final themeColors   = kThemeColors(_gradientIndex);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: Column(children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 64, height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: themeColors, begin: Alignment.topLeft, end: Alignment.bottomRight,
                  stops: themeColors.length >= 3 ? const [0.0, 0.5, 1.0] : null),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: themeColors[0].withOpacity(0.5), blurRadius: 14)]),
              child: Center(child: Text(_emoji,
                style: TextStyle(
                  fontSize: _isLegacyEmoji ? 32 : 26,
                  color: Colors.white, fontWeight: FontWeight.w900)))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nameCtrl.text.isEmpty ? 'Your Name' : _nameCtrl.text,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
              const SizedBox(height: 2),
              Text(kBannerThemes[_gradientIndex]['name'] as String,
                style: TextStyle(fontSize: 12, color: themeColors.last, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text((_selectedBranch != null && _selectedYear != null)
                  ? '$_selectedBranch • Year $_selectedYear' : 'Student',
                style: TextStyle(fontSize: 12, color: textSecondary)),
            ])),
          ]),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: surfaceVar, borderRadius: BorderRadius.circular(14)),
            child: TabBar(controller: _tabCtrl,
              indicator: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white, unselectedLabelColor: textSecondary,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [Tab(text: '👤 Info'), Tab(text: '🎨 Look'), Tab(text: '✏️ Bio')])),
        ])),

        Expanded(child: TabBarView(controller: _tabCtrl, children: [
          _buildInfoTab(textColor, textSecondary, surfaceVar, primary),
          _buildLookTab(textColor, textSecondary, surfaceVar, primary),
          _buildBioTab(textColor, textSecondary, surfaceVar),
        ])),

        Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SizedBox(width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: () {
                widget.onSave(_emoji, _gradientIndex, _bioCtrl.text.trim(),
                  _nameCtrl.text.trim(), _selectedBranch ?? '', _selectedYear ?? '',
                  _usernameCtrl.text.trim().toLowerCase());
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              child: Text('Save Profile',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))))),
      ]));
  }

  Widget _buildInfoTab(Color textColor, Color textSecondary, Color surfaceVar, Color primary) =>
    SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Display Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
      const SizedBox(height: 8),
      TextField(controller: _nameCtrl, maxLength: 30,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Enter your name', hintStyle: TextStyle(color: textSecondary),
          filled: true, fillColor: surfaceVar, counterStyle: TextStyle(color: textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          prefixIcon: Icon(Icons.person_outline, color: primary))),
      const SizedBox(height: 20),
      Row(children: [
        Text('Username', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
        const SizedBox(width: 8),
        if (_usernameChangeCoolingDown)
          Text('· next change on $_nextChangeDate',
            style: TextStyle(fontSize: 11, color: textSecondary))
        else
          Text('· can change once/month',
            style: TextStyle(fontSize: 11, color: textSecondary)),
      ]),
      const SizedBox(height: 8),
      IgnorePointer(
        ignoring: _usernameChangeCoolingDown,
        child: TextField(
          controller: _usernameCtrl,
          maxLength: 20,
          style: TextStyle(color: _usernameChangeCoolingDown ? textSecondary : textColor, fontWeight: FontWeight.w600),
          onChanged: (val) {
            final clean = val.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
            if (clean != val) {
              _usernameCtrl.value = _usernameCtrl.value.copyWith(
                text: clean, selection: TextSelection.collapsed(offset: clean.length));
            }
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: 'e.g. ayush_01', hintStyle: TextStyle(color: textSecondary),
            filled: true, fillColor: _usernameChangeCoolingDown ? surfaceVar.withValues(alpha: 0.5) : surfaceVar,
            counterStyle: TextStyle(color: textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            prefixIcon: Icon(Icons.alternate_email_rounded, color: _usernameChangeCoolingDown ? textSecondary : primary)),
        ),
      ),
      const SizedBox(height: 8),
      Text('Branch', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: kBranches.map((b) {
        final sel = b == _selectedBranch;
        return GestureDetector(onTap: () => setState(() => _selectedBranch = b),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? primary.withOpacity(0.15) : surfaceVar,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? primary : Colors.transparent, width: 2)),
            child: Text(b, style: TextStyle(color: sel ? primary : textSecondary,
              fontWeight: FontWeight.w700, fontSize: 13))));
      }).toList()),
      const SizedBox(height: 20),
      Text('Year', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
      const SizedBox(height: 10),
      Row(children: kYears.map((y) {
        final sel = y == _selectedYear;
        return Expanded(child: GestureDetector(onTap: () => setState(() => _selectedYear = y),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: sel ? primary.withOpacity(0.15) : surfaceVar,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? primary : Colors.transparent, width: 2)),
            child: Center(child: Text('Yr $y', style: TextStyle(
              color: sel ? primary : textSecondary, fontWeight: FontWeight.w800, fontSize: 14))))));
      }).toList()),
    ]));

  Widget _buildLookTab(Color textColor, Color textSecondary, Color surfaceVar, Color primary) {
    final themeColors = kThemeColors(_gradientIndex);

    const categories = [
      {'label': '♔  Royalty',   'start': 0,  'end': 5},
      {'label': '✦  Celestial', 'start': 6,  'end': 11},
      {'label': '◈  Crests',    'start': 12, 'end': 17},
      {'label': 'Ω  Script',    'start': 18, 'end': 23},
      {'label': '❧  Floral',    'start': 24, 'end': 29},
      {'label': '⚔  Arcane',    'start': 30, 'end': 35},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(children: [
          Container(width: 3, height: 16,
            decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('Avatar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
          const Spacer(),
          Text('tap to select', style: TextStyle(fontSize: 11, color: textSecondary)),
        ]),
        const SizedBox(height: 14),

        ...categories.map((cat) {
          final start = cat['start'] as int;
          final end   = cat['end']   as int;
          final items = kAvatarSymbols.sublist(start, end + 1);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(bottom: 8, top: 2),
              child: Text(cat['label'] as String,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: textSecondary, letterSpacing: 0.8))),
            Wrap(spacing: 8, runSpacing: 8, children: items.map((item) {
              final sym = item['s']!;
              final sel = sym == _emoji;
              return GestureDetector(
                onTap: () => setState(() => _emoji = sym),
                child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: sel ? LinearGradient(
                      colors: themeColors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      stops: themeColors.length >= 3 ? const [0.0, 0.5, 1.0] : null) : null,
                    color: sel ? null : surfaceVar,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? themeColors.last.withOpacity(0.6) : Colors.transparent, width: 2),
                    boxShadow: sel
                      ? [BoxShadow(color: themeColors[0].withOpacity(0.5), blurRadius: 12)] : []),
                  child: Center(child: Text(sym,
                    style: TextStyle(
                      fontSize: 22,
                      color: sel ? Colors.white : textColor.withOpacity(0.85),
                      fontWeight: FontWeight.w900)))));
            }).toList()),
            const SizedBox(height: 10),
          ]);
        }).toList(),

        if (_isLegacyEmoji) ...[
          Padding(padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text('🎭  Classic Emoji',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: textSecondary, letterSpacing: 0.8))),
          Wrap(spacing: 8, runSpacing: 8, children: kAvatarEmojis.map((e) {
            final sel = e == _emoji;
            return GestureDetector(
              onTap: () => setState(() => _emoji = e),
              child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: sel ? primary.withOpacity(0.15) : surfaceVar,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: sel ? primary : Colors.transparent, width: 2)),
                child: Center(child: Text(e, style: TextStyle(fontSize: 26)))));
          }).toList()),
          const SizedBox(height: 16),
        ],

        const SizedBox(height: 8),

        Row(children: [
          Container(width: 3, height: 16,
            decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('Card Theme', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
          const Spacer(),
          Text('${kBannerThemes.length} themes', style: TextStyle(fontSize: 11, color: textSecondary)),
        ]),
        const SizedBox(height: 14),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10,
            childAspectRatio: 0.78),
          itemCount: kBannerThemes.length,
          itemBuilder: (_, i) {
            final sel    = i == _gradientIndex;
            final colors = kThemeColors(i);
            final name   = kBannerThemes[i]['name'] as String;
            return GestureDetector(
              onTap: () => setState(() => _gradientIndex = i),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight,
                    stops: colors.length >= 3 ? const [0.0, 0.5, 1.0] : null),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2.5),
                  boxShadow: sel ? [BoxShadow(
                    color: colors[0].withOpacity(0.55), blurRadius: 14,
                    offset: const Offset(0, 4))] : []),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (sel)
                    Icon(Icons.check_rounded, color: Colors.white, size: 18)
                  else
                    const SizedBox(height: 18),
                  const SizedBox(height: 4),
                  Text(name,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withOpacity(sel ? 1.0 : 0.8),
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: 0.2),
                    textAlign: TextAlign.center),
                ])));
          }),

        const SizedBox(height: 16),
      ]));
  }

  Widget _buildBioTab(Color textColor, Color textSecondary, Color surfaceVar) =>
    Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('About You', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
        const SizedBox(height: 8),
        Text('Write something cool (max 80 chars)', style: TextStyle(fontSize: 12, color: textSecondary)),
        const SizedBox(height: 12),
        TextField(controller: _bioCtrl, maxLength: 80, maxLines: 4,
          style: TextStyle(color: textColor, height: 1.5),
          decoration: InputDecoration(
            hintText: 'e.g. "DSA grinder by day, UNO champion by night 🃏"',
            hintStyle: TextStyle(color: textSecondary, fontSize: 13),
            filled: true, fillColor: surfaceVar, counterStyle: TextStyle(color: textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
      ]));
}

// ── Friends tab ───────────────────────────────────────────────────────────────
class _FriendsTab extends StatelessWidget {
  final List<Map<String, dynamic>> friends;
  final bool loading;
  final Color textColor, textSecondary, surfaceVar;
  const _FriendsTab({required this.friends, required this.loading, required this.textColor, required this.textSecondary, required this.surfaceVar});

  @override
  Widget build(BuildContext context) {
    if (loading) return Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (friends.isEmpty) return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('👥', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('No friends yet.\nStart connecting!', textAlign: TextAlign.center,
          style: TextStyle(color: textSecondary, fontSize: 14))])));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final f      = friends[i];
        final name   = f['username']?.toString() ?? 'User';
        final branch = f['branch']?.toString() ?? '';
        final avatar = f['avatar_emoji']?.toString() ?? '♔';
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserProfileScreen(userId: f['id']?.toString() ?? ''))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: surfaceVar, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Builder(builder: (_) {
                final bannerIdx = ((f['banner_index'] as num?)?.toInt() ?? 0)
                    .clamp(0, kBannerThemes.length - 1);
                final avatarColor = kThemeColors(bannerIdx).first;
                return Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [
                      avatarColor.withOpacity(0.5),
                      avatarColor.withOpacity(0.2),
                    ]),
                    shape: BoxShape.circle,
                    border: Border.all(color: avatarColor.withOpacity(0.4), width: 1.5)),
                  child: Center(child: Text(avatar, style: TextStyle(fontSize: 20))));
              }),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: textColor, fontSize: 14)),
                if (branch.isNotEmpty)
                  Text(branch, style: TextStyle(fontSize: 12, color: textSecondary)),
              ])),
              Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF6C63FF)),
            ]),
          ),
        );
      },
    );
  }
}

// ── Requests tab ──────────────────────────────────────────────────────────────
class _RequestsTab extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final bool loading;
  final Color textColor, textSecondary, surfaceVar;
  final VoidCallback onRefresh;
  const _RequestsTab({required this.requests, required this.loading, required this.textColor, required this.textSecondary, required this.surfaceVar, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading) return Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (requests.isEmpty) return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('📨', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('No pending requests.', textAlign: TextAlign.center,
          style: TextStyle(color: textSecondary, fontSize: 14))])));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r        = requests[i];
        final name     = r['username']?.toString() ?? 'User';
        final branch   = r['branch']?.toString() ?? '';
        final avatar   = r['avatar_emoji']?.toString() ?? '♔';
        final senderId = r['sender_id']?.toString() ?? '';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB800).withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3))),
          child: Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(color: Color(0xFFFFB800), shape: BoxShape.circle),
              child: Center(child: Text(avatar, style: TextStyle(fontSize: 20)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: textColor, fontSize: 14)),
              if (branch.isNotEmpty)
                Text(branch, style: TextStyle(fontSize: 12, color: textSecondary)),
            ])),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _RequestBtn(label: '✓', color: Colors.green, onTap: () async {
                try {
                  await supabase.from('friendships').update({'status': 'accepted'})
                    .eq('sender_id', senderId)
                    .eq('receiver_id', supabase.auth.currentUser!.id);
                  onRefresh();
                } catch (_) {}
              }),
              const SizedBox(width: 6),
              _RequestBtn(label: '✕', color: Colors.red, onTap: () async {
                try {
                  await supabase.from('friendships').delete()
                    .eq('sender_id', senderId)
                    .eq('receiver_id', supabase.auth.currentUser!.id);
                  onRefresh();
                } catch (_) {}
              }),
            ]),
          ]),
        );
      },
    );
  }
}

// ── Posts tab ────────────────────────────────────────────────────────────────
class _PostsTab extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final bool loading;
  final Set<String> likedPostIds;
  final Future<void> Function(String, int) onLike;
  final void Function(String, String, String) onOpenComments;
  const _PostsTab({required this.posts, required this.loading, required this.likedPostIds, required this.onLike, required this.onOpenComments});
  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab> {
  int _subTab = 0;

  String _fmt(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final d  = DateTime.now().difference(dt);
      if (d.inMinutes < 1)  return 'just now';
      if (d.inMinutes < 60) return '${d.inMinutes}m ago';
      if (d.inHours < 24)   return '${d.inHours}h ago';
      if (d.inDays < 7)     return '${d.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }

  void _showLikes(BuildContext ctx, String postId) => showModalBottomSheet(
    context: ctx, backgroundColor: Colors.transparent, isScrollControlled: true,
    builder: (_) => _LikesSheet(postId: postId));

  void _fullImage(BuildContext ctx, String url) => Navigator.push(ctx, PageRouteBuilder(
    opaque: false, barrierColor: Colors.black87, barrierDismissible: true,
    pageBuilder: (_, __, ___) => GestureDetector(
      onTap: () => Navigator.pop(ctx), behavior: HitTestBehavior.opaque,
      child: Scaffold(backgroundColor: Colors.transparent,
        body: Center(child: GestureDetector(onTap: () {},
          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64))))))),
    transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)));

  @override
  Widget build(BuildContext context) {
    final textColor     = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surface       = AppColors.surface(context);
    final border        = AppColors.border(context);
    const indigo = Color(0xFF818CF8);
    const pink   = Color(0xFFE879F9);

    if (widget.loading) return Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)));
    if (widget.posts.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('📭', style: TextStyle(fontSize: 36)),
      const SizedBox(height: 8),
      Text('No public posts yet', style: TextStyle(color: textSecondary, fontSize: 13))]));

    final imgPosts  = widget.posts.where((p) => (p['image_url'] as String?)?.isNotEmpty == true).toList();
    final txtPosts  = widget.posts.where((p) => (p['image_url'] as String?)?.isEmpty != false).toList();

    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _SubTab(icon: Icons.grid_on_rounded,           selected: _subTab == 0, onTap: () => setState(() => _subTab = 0)),
          const SizedBox(width: 8),
          _SubTab(icon: Icons.format_align_left_rounded, selected: _subTab == 1, onTap: () => setState(() => _subTab = 1)),
        ])),
      Expanded(child: _subTab == 0
        ? (imgPosts.isEmpty
            ? Center(child: Text('No photo posts yet', style: TextStyle(color: textSecondary, fontSize: 13)))
            : GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2, childAspectRatio: 1),
                itemCount: imgPosts.length,
                itemBuilder: (ctx, i) {
                  final p      = imgPosts[i];
                  final postId = p['id']?.toString() ?? '';
                  final url    = p['image_url'] as String? ?? '';
                  final likes  = (p['likes'] as num?)?.toInt() ?? 0;
                  final isLiked = widget.likedPostIds.contains(postId);
                  return GestureDetector(
                    onTap: () => _fullImage(ctx, url),
                    onLongPress: () => _showLikes(ctx, postId),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: surface,
                          child: Icon(Icons.broken_image_rounded, color: Colors.white24, size: 28))),
                      Positioned(bottom: 4, left: 4,
                        child: GestureDetector(
                          onTap: () => widget.onLike(postId, likes),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 13, color: isLiked ? Colors.red : Colors.white70),
                            const SizedBox(width: 2),
                            Text('$likes', style: TextStyle(color: Colors.white70, fontSize: 10,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                          ]))),
                    ]));
                }))
        : (txtPosts.isEmpty
            ? Center(child: Text('No text posts yet', style: TextStyle(color: textSecondary, fontSize: 13)))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: txtPosts.length,
                separatorBuilder: (_, __) => Divider(color: border, height: 1),
                itemBuilder: (ctx, i) {
                  final p        = txtPosts[i];
                  final postId   = p['id']?.toString() ?? '';
                  final ownerId  = p['user_id']?.toString() ?? '';
                  final content  = p['content']?.toString() ?? '';
                  final likes    = (p['likes'] as num?)?.toInt() ?? 0;
                  final comments = (p['comment_count'] as num?)?.toInt() ?? 0;
                  final isLiked  = widget.likedPostIds.contains(postId);
                  return GestureDetector(
                    onLongPress: () => _showLikes(ctx, postId),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(content, style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
                          maxLines: 5, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(children: [
                          GestureDetector(
                            onTap: () => widget.onLike(postId, likes),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 15, color: isLiked ? pink : textSecondary),
                              const SizedBox(width: 4),
                              Text('$likes', style: TextStyle(color: isLiked ? pink : textSecondary,
                                fontSize: 12, fontWeight: FontWeight.w600)),
                            ])),
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: () => widget.onOpenComments(postId, ownerId, content),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: indigo),
                              const SizedBox(width: 4),
                              Text('$comments', style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                            ])),
                          const Spacer(),
                          Text(_fmt(p['created_at']?.toString() ?? ''),
                            style: TextStyle(color: textSecondary, fontSize: 11)),
                        ]),
                      ])));
                }))),
    ]);
  }
}

class _SubTab extends StatelessWidget {
  final IconData icon; final bool selected; final VoidCallback onTap;
  const _SubTab({required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF818CF8).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? const Color(0xFF818CF8).withOpacity(0.4) : Colors.transparent)),
      child: Icon(icon, size: 20,
        color: selected ? const Color(0xFF818CF8) : AppColors.textSecondary(context))));
}

// ── Likes sheet ────────────────────────────────────────────────────────────────
class _LikesSheet extends StatefulWidget {
  final String postId;
  const _LikesSheet({required this.postId});
  @override State<_LikesSheet> createState() => _LikesSheetState();
}

class _LikesSheetState extends State<_LikesSheet> {
  List<Map<String, dynamic>> _likers = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from('buzz_likes')
          .select('user_id, profiles(username, avatar_emoji, branch_name)')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() {
        _likers = List<Map<String, dynamic>>.from((rows as List).map((r) {
          final p = r['profiles'] as Map? ?? {};
          return {
            'user_id': r['user_id']?.toString() ?? '',
            'name':    p['username']?.toString() ?? 'User',
            'avatar':  p['avatar_emoji']?.toString() ?? '♔',
            'branch':  p['branch_name']?.toString() ?? '',
          };
        }));
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final textColor     = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surface       = AppColors.surface(context);
    return Container(
      decoration: BoxDecoration(color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Icon(Icons.favorite_rounded, size: 18, color: Color(0xFFE879F9)),
            const SizedBox(width: 8),
            Text('Liked by', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w800)),
          ])),
        const SizedBox(height: 12),
        if (_loading)
          Padding(padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)))
        else if (_likers.isEmpty)
          Padding(padding: const EdgeInsets.all(32),
            child: Text('No likes yet', style: TextStyle(color: textSecondary)))
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _likers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final l = _likers[i];
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => UserProfileScreen(userId: l['user_id'])));
                  },
                  child: Row(children: [
                    Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: Color(0xFF6C63FF), shape: BoxShape.circle),
                      child: Center(child: Text(l['avatar'], style: TextStyle(fontSize: 18)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l['name'], style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                      if ((l['branch'] as String).isNotEmpty)
                        Text(l['branch'], style: TextStyle(color: textSecondary, fontSize: 12)),
                    ])),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF6C63FF)),
                  ]));
              })),
      ]));
  }
}