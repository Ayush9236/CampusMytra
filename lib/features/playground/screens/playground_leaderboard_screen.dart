import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../settings/theme_provider.dart';

class PlaygroundLeaderboardScreen extends StatefulWidget {
  const PlaygroundLeaderboardScreen({Key? key}) : super(key: key);

  @override
  State<PlaygroundLeaderboardScreen> createState() =>
      _PlaygroundLeaderboardScreenState();
}

class _PlaygroundLeaderboardScreenState
    extends State<PlaygroundLeaderboardScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _unoLeaderboard = [];
  List<Map<String, dynamic>> _dsaLeaderboard = [];
  bool _loading = true;
  int _selectedTab = 0;
  String _myId = '';

  static const _kPurple = Color(0xFF6C63FF);
  static const _kRed    = Color(0xFFFF375F);

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id ?? '';
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final unoRaw = await supabase.rpc('get_uno_leaderboard');
      final dsaRaw = await supabase.rpc('get_dsa_leaderboard', params: {'p_limit': 50});

      final unoIds = (unoRaw as List).map((r) => r['user_id'].toString()).toList();
      final dsaIds = (dsaRaw as List).map((r) => r['user_id'].toString()).toList();
      final allIds = {...unoIds, ...dsaIds}.toList();

      final Map<String, Map<String, dynamic>> profileMap = {};
      if (allIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('profiles')
              .select('id, username, avatar_emoji')
              .inFilter('id', allIds);
          for (final p in profiles as List) {
            profileMap[p['id'].toString()] = Map<String, dynamic>.from(p as Map);
          }
        } catch (_) {}
      }

      final unoBoard = unoRaw.map<Map<String, dynamic>>((row) {
        final p = profileMap[row['user_id'].toString()] ?? {};
        return {
          'user_id': row['user_id'].toString(),
          'games_won': row['games_won'] ?? 0,
          'name': p['username']?.toString() ?? 'Unknown',
          'avatar_emoji': p['avatar_emoji']?.toString() ?? '🎓',
        };
      }).toList();

      final dsaBoard = dsaRaw.map<Map<String, dynamic>>((row) {
        final p = profileMap[row['user_id'].toString()] ?? {};
        return {
          'user_id': row['user_id'].toString(),
          'solved': row['wins'] ?? 0,
          'name': p['username']?.toString() ?? 'Unknown',
          'avatar_emoji': p['avatar_emoji']?.toString() ?? '🎓',
        };
      }).toList();

      if (mounted) setState(() {
        _unoLeaderboard = unoBoard;
        _dsaLeaderboard = dsaBoard;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _medal(int rank) {
    switch (rank) {
      case 1: return '🥇';
      case 2: return '🥈';
      case 3: return '🥉';
      default: return '#$rank';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUno = _selectedTab == 0;
    final board = isUno ? _unoLeaderboard : _dsaLeaderboard;
    final accentColor = isUno ? _kRed : _kPurple;
    final bg = AppColors.background(context);
    final surface = AppColors.surface(context);
    final text = AppColors.text(context);
    final textSec = AppColors.textSecondary(context);
    final border = AppColors.border(context);
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textSec, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🏆 Leaderboard',
              style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 17)),
          Text('Top players on campus',
              style: TextStyle(color: textSec, fontSize: 10, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textSec, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(children: [
        // Tab switcher
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Row(children: [
            _buildTab('🎮 UNO', 0, _kRed, isDark, border),
            const SizedBox(width: 10),
            _buildTab('⚔️ DSA Combat', 1, _kPurple, isDark, border),
          ]),
        ),
        const SizedBox(height: 16),

        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.2)),
            ),
            child: Row(children: [
              const SizedBox(width: 32),
              Expanded(
                child: Text('Player',
                    style: TextStyle(color: textSec,
                        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
              Text(isUno ? 'Wins' : 'Solved',
                  style: TextStyle(color: textSec,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(height: 8),

        // List
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accentColor, strokeWidth: 2))
              : board.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(isUno ? '🎮' : '⚔️', style: const TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      Text('No data yet — ${isUno ? 'play UNO' : 'battle in DSA'}!',
                          style: TextStyle(color: textSec, fontSize: 14)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: accentColor,
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                        itemCount: board.length,
                        itemBuilder: (ctx, i) {
                          final row = board[i];
                          final isMe = row['user_id'] == _myId;
                          final rank = i + 1;
                          final name = row['name']?.toString().split(' ')[0] ?? 'Unknown';
                          final avatar = row['avatar_emoji']?.toString() ?? '🎓';
                          final value = isUno
                              ? '${row['games_won'] ?? 0} wins'
                              : '✅ ${row['solved'] ?? 0}';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              gradient: rank <= 3
                                  ? LinearGradient(colors: [
                                      accentColor.withOpacity(isMe ? 0.15 : 0.07),
                                      surface,
                                    ], begin: Alignment.centerLeft, end: Alignment.centerRight)
                                  : null,
                              color: rank > 3 ? (isMe ? accentColor.withOpacity(0.1) : surface) : null,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: rank <= 3
                                    ? accentColor.withOpacity(0.25)
                                    : isMe
                                        ? accentColor.withOpacity(0.35)
                                        : border,
                              ),
                              boxShadow: rank == 1 ? [BoxShadow(
                                color: accentColor.withOpacity(0.15),
                                blurRadius: 16, offset: const Offset(0, 4))] : [],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              child: Row(children: [
                                SizedBox(
                                  width: 36,
                                  child: rank <= 3
                                      ? Text(_medal(rank), style: const TextStyle(fontSize: 20))
                                      : Text('#$rank', style: TextStyle(
                                          color: textSec,
                                          fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                Text(avatar, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(isMe ? '$name (you)' : name,
                                      style: TextStyle(
                                        color: isMe ? accentColor : text,
                                        fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 14,
                                      )),
                                  if (rank == 1)
                                    Text('Campus Champion', style: TextStyle(
                                        color: accentColor.withOpacity(0.6),
                                        fontSize: 10, fontWeight: FontWeight.w600)),
                                ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: accentColor.withOpacity(0.25)),
                                  ),
                                  child: Text(value,
                                      style: TextStyle(color: accentColor,
                                          fontWeight: FontWeight.w800, fontSize: 12)),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildTab(String label, int index, Color color, bool isDark, Color border) {
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? color : (isDark ? Colors.white38 : Colors.black38),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              fontSize: 13,
            )),
      ),
    );
  }
}
